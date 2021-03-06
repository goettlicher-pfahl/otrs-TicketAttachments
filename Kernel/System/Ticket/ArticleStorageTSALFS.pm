# --
# Kernel/System/Ticket/ArticleStorageTSALFS.pm - article storage module for OTRS kernel
# Copyright (C) 2012 - 2014 Perl-Services.de, http://perl-services.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Ticket::ArticleStorageTSALFS;

use strict;
use warnings;

use Kernel::System::Ticket::ArticleStorageFS;

our @ISA = qw(Kernel::System::Ticket::ArticleStorageFS);

sub AttachmentExists {
    my ($Self, %Param) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
    
    # check needed stuff
    for my $Needed (qw(ArticleID Filename)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message => "Need $Needed!",
            );
            return;
        }
    }

    my $ContentPath = $Self->ArticleGetContentPath( ArticleID => $Param{ArticleID} );
    my $Path = "$Self->{ArticleDataDir}/$ContentPath/$Param{ArticleID}/$Param{Filename}";

    return 1 if -f $Path;
    return;
}

sub AttachmentSetCategory {
    my ($Self, %Param) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $DBObject     = $Kernel::OM->Get('Kernel::System::DB');
    my $MainObject   = $Kernel::OM->Get('Kernel::System::Main');
    
    # check needed stuff
    for my $Needed (qw(ArticleID UserID FileID TicketID Filename Category)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message => "Need $Needed!",
            );
            return;
        }
    }

    my $Debug = $ConfigObject->Get( 'Attachmentlist::Debug' );

    $Param{Filename} = $MainObject->FilenameCleanUp(
        Filename => $Param{Filename},
        Type     => 'Local',
    );

    my $AttachmentExists = $Self->AttachmentExists( %Param );

    if ( $Debug && $AttachmentExists ) {
        $LogObject->Log(
            Priority => 'debug',
            Message  => "Attachment exists",
        );
    }

    if ( $AttachmentExists && !$Param{Force} ) {
        $LogObject->Log(
            Priority => 'error',
            Message => "Attachment already exists!",
        );
        return;
    }

    my ($AttachmentID, $Filename) = $Self->_AttachmentInfoGet( %Param );

    if ( $Debug ) {
        $LogObject->Log(
            Priority => 'debug',
            Message  => "Set Category for ID $AttachmentID // File $Filename",
        );
    }

    return if !$AttachmentID;
    return if !$Filename;

    if ( $Debug ) {
        $LogObject->Log(
            Priority => 'debug',
            Message  => "Path: $Path",
        );
    }

    # add history entry
    $Self->HistoryAdd(
        TicketID     => $Param{TicketID},
        ArticleID    => $Param{ArticleID},
        HistoryType  => 'AttachmentSetCategory',
        Name         => "\%\%$Filename\%\%$Param{Category}",
        CreateUserID => $Param{UserID},
    );

    $Self->EventHandler(
        Event => 'AttachmentSetCategory',
        Data  => {
            ArticleID => $Param{ArticleID},
            FileID    => $AttachmentID,
            Filename  => $Filename,
            TicketID  => $Param{TicketID},
            Category  => $Param{Category},
        },
        UserID => $Param{UserID},
    );

    # return if only rename in my backend
    return 1 if $Param{OnlyMyBackend};

    # set category for attachment in database
    return if !$DBObject->Do(
        SQL  => 'UPDATE article_attachment SET category = ? WHERE article_id = ? AND id = ?',
        Bind => [ \$Param{Category}, \$Param{ArticleID}, \$AttachmentID ],
    );

    return 1;
}


sub AttachmentRename {
    my ($Self, %Param) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $DBObject     = $Kernel::OM->Get('Kernel::System::DB');
    my $MainObject   = $Kernel::OM->Get('Kernel::System::Main');
    
    # check needed stuff
    for my $Needed (qw(ArticleID UserID FileID TicketID Filename)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message => "Need $Needed!",
            );
            return;
        }
    }

    my $Debug = $ConfigObject->Get( 'Attachmentlist::Debug' );

    $Param{Filename} = $MainObject->FilenameCleanUp(
        Filename => $Param{Filename},
        Type     => 'Local',
    );

    my $AttachmentExists = $Self->AttachmentExists( %Param );

    if ( $Debug && $AttachmentExists ) {
        $LogObject->Log(
            Priority => 'debug',
            Message  => "Attachment exists",
        );
    }

    if ( $AttachmentExists && !$Param{Force} ) {
        $LogObject->Log(
            Priority => 'error',
            Message => "Attachment already exists!",
        );
        return;
    }

    my ($AttachmentID, $Filename) = $Self->_AttachmentInfoGet( %Param );

    if ( $Debug ) {
        $LogObject->Log(
            Priority => 'debug',
            Message  => "Rename ID $AttachmentID // File $Filename",
        );
    }

    return if !$AttachmentID;
    return if !$Filename;

    my $ContentPath = $Self->ArticleGetContentPath( ArticleID => $Param{ArticleID} );
    my $Path = "$Self->{ArticleDataDir}/$ContentPath/$Param{ArticleID}";

    if ( $Debug ) {
        $LogObject->Log(
            Priority => 'debug',
            Message  => "Path: $Path",
        );
    }

    if ( -e $Path ) {
        my @List = $MainObject->DirectoryRead(
            Directory => $Path,
            Filter    => "*",
        );

        FILE:
        for my $File (@List) {

            if ( $Debug ) {
                $LogObject->Log(
                    Priority => 'debug',
                    Message  => "Try $File // $Filename -> $Param{Filename}",
                );
            }

            next FILE if $File !~ m{ / \Q$Filename\E (?:\.content_ (?:type|alternative|id) | \.disposition)? \z}xms;

            (my $NewPath = $File) =~ s{
                \Q$Filename\E
                (
                    \.content_ (?:type|alternative|id) |
                    \.disposition
                )?
                \z
            }{$Param{Filename}$1}xms;

            if ( $Debug ) {
                $LogObject->Log(
                    Priority => 'debug',
                    Message  => "Old: $File // New: $NewPath",
                );
            }

            if ( !rename $File, $NewPath ) {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "Can't rename: $File to $Param{Filename}: $!!",
                );
            }
        }
    }

    # add history entry
    $Self->HistoryAdd(
        TicketID     => $Param{TicketID},
        ArticleID    => $Param{ArticleID},
        HistoryType  => 'AttachmentRename',
        Name         => "\%\%$Filename\%\%$Param{Filename}",
        CreateUserID => $Param{UserID},
    );

    $Self->EventHandler(
        Event => 'AttachmentRename',
        Data  => {
            ArticleID => $Param{ArticleID},
            FileID    => $AttachmentID,
            Filename  => $Filename,
            TicketID  => $Param{TicketID},
        },
        UserID => $Param{UserID},
    );

    # rename attachment in filesystem
    # return if only delete in my backend
    return 1 if $Param{OnlyMyBackend};

    # rename attachment in database
    return if !$DBObject->Do(
        SQL  => 'UPDATE article_attachment SET filename = ? WHERE article_id = ? AND id = ?',
        Bind => [ \$Param{Filename}, \$Param{ArticleID}, \$AttachmentID ],
    );

    return 1;
}

sub ArticleDeleteSingleAttachment {
    my ($Self, %Param) = @_;
    
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $DBObject     = $Kernel::OM->Get('Kernel::System::DB');
    my $MainObject   = $Kernel::OM->Get('Kernel::System::Main');
    
    # check needed stuff
    for my $Needed (qw(ArticleID UserID FileID TicketID)) {
        if ( !$Param{$Needed} ) {
            $LogObject->Log(
                Priority => 'error',
                Message => "Need $Needed!",
            );
            return;
        }
    }

    my ($AttachmentID, $Filename) = $Self->_AttachmentInfoGet( %Param );

    return if !$AttachmentID;
    return if !$Filename;

    # delete from fs
    my $ContentPath = $Self->ArticleGetContentPath( ArticleID => $Param{ArticleID} );
    my $Path = "$Self->{ArticleDataDir}/$ContentPath/$Param{ArticleID}";
    if ( -e $Path ) {
        my @List = $MainObject->DirectoryRead(
            Directory => $Path,
            Filter    => "*",
            Silent    => 1,
        );

        FILE:
        for my $File (@List) {

            next FILE if $File !~ m{ / \Q$Filename\E (?: \.content_ (?:type|alternative|id) | \.disposition )? \z }xms;
            next FILE if $File =~ m{ / plain\.txt $ }xms;
            next FILE if $File =~ m{ /file-[12] $ }xms;

            if ( !unlink "$File" ) {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "Can't remove: $File: $!!",
                );
            }
        }
    }

    # add history entry
    $Self->HistoryAdd(
        TicketID     => $Param{TicketID},
        ArticleID    => $Param{ArticleID},
        HistoryType  => 'AttachmentDelete',
        Name         => "\%\%$Filename",
        CreateUserID => $Param{UserID},
    );

    # trigger event
    $Self->EventHandler(
        Event => 'SingleTicketAttachmentDelete',
        Data  => {
            ArticleID => $Param{ArticleID},
            FileID    => $AttachmentID,
            Filename  => $Filename,
            TicketID  => $Param{TicketID},
        },
        UserID => $Param{UserID},
    );

    # return if only delete in my backend
    return 1 if $Param{OnlyMyBackend};

    # delete attachments from db
    return if !$DBObject->Do(
        SQL  => 'DELETE FROM article_attachment WHERE article_id = ? AND id = ?',
        Bind => [
            \$Param{ArticleID},
            \$AttachmentID,
        ],
    );

    return 1;
}

sub _AttachmentInfoGet {
    my ($Self, %Param) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $MainObject   = $Kernel::OM->Get('Kernel::System::Main');
    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');

    my $Debug = $ConfigObject->Get( 'Attachmentlist::Debug' );
    
    my $AttachmentID = 0;
    my $Filename;
    my $Filesize;

    my $ContentPath = $Self->ArticleGetContentPath( ArticleID => $Param{ArticleID} );
    my $Path = "$Self->{ArticleDataDir}/$ContentPath/$Param{ArticleID}";

    my $FilenameToCheck = basename( $Param{Filename} // '' );

    if ( $Debug ) {
        $LogObject->Log(
            Priority => 'debug',
            Message  => $MainObject->Dump( \%Param ),
        );
    }

    if ( $Debug ) {
        $LogObject->Log(
            Priority => 'debug',
            Message  => $MainObject->Dump( [ $Path, $FilenameToCheck ] ),
        );
    }

    if ( -e $Path ) {
        my @List = $MainObject->DirectoryRead(
            Directory => $Path,
            Filter    => "*",
            Silent    => 1,
        );

        FILE:
        for my $File ( sort @List ) {

            if ( $Debug ) {
                $LogObject->Log(
                    Priority => 'debug',
                    Message  => "File: $File",
                );
            }

            next FILE if $File =~ m{ (?: \.content_ (?:alternative|type|id) | \.disposition ) $}xms;
            next FILE if $File =~ m{/plain\.txt$};

            next FILE if !-e "$File.content_type";

            if ( $File =~ m{/file-2$}xms ) {
                $AttachmentID++;
            }

            next FILE if $File =~ m{/file-[12]$}xms;

            my %TmpInfo;
            my $ContentType = $MainObject->FileRead(
                Location => "$File.content_type",
            );

            next FILE if !$ContentType;

            $TmpInfo{ContentType} = ${$ContentType};

            if ( -e "$File.content_id" ) {
                my $ContentID = $MainObject->FileRead(
                    Location => "$File.content_id",
                );

                $TmpInfo{ContentID} = ${$ContentID};
            }

            if ( -e "$File.disposition" ) {
                my $Disposition = $MainObject->FileRead(
                    Location => "$File.disposition",
                );

                $TmpInfo{Disposition} = ${$Disposition};
            }

            if ( $Debug ) {
                $LogObject->Log(
                    Priority => 'debug',
                    Message  => $MainObject->Dump( \%TmpInfo ),
                );
            }

            next FILE if $TmpInfo{Disposition} && 'inline' eq lc $TmpInfo{Disposition};
            next FILE if $TmpInfo{ContentID} && $TmpInfo{ContentType} =~ m{image}ixms;

            $Filesize = -s $File;

            $File =~ s{^.*/}{};

            $Filename = $File;
            $AttachmentID++;

            if ( $Debug ) {
                $LogObject->Log(
                    Priority => 'debug',
                    Message  => $MainObject->Dump( [ $Filename, $AttachmentID ] ),
                );
            }

            if ( $Param{FileID} && $Param{FileID} == $AttachmentID ) {
                last FILE;
            }
            elsif ( $FilenameToCheck && $FilenameToCheck eq basename($File) ) {
                last FILE;
            }
        }
    }

    if ( $Debug ) {
        $LogObject->Log(
            Priority => 'debug',
            Message  => "Filename: $Filename // Filesize: $Filesize",
        );
    }

    return if !$AttachmentID;
    return if !$Filename;

    my $Size = _FormatSize( $Filesize );

    if ( $Debug ) {
        $LogObject->Log(
            Priority => 'debug',
            Message  => "Size: $Size // $Filesize",
        );
    }

    return ($AttachmentID, $Filename, $Size);
}

sub _FormatSize {
    my ($Size) = @_;

    my $Formatted = "$Size B";
    my $KB        = 1024;

    if ( $Size > $KB * 1024 ) {
        $Formatted = sprintf "%.2f MB", $Size / ( $KB * 1024 );
    }
    elsif ( $Size > $KB ) {
        $Formatted = sprintf "%.2f KB", $Size / $KB;
    }

    return $Formatted;
}

sub _TicketIDsGet {
    my ($Self, %Param) = @_;

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    
    return if !$Param{ArticleIDs} || ref $Param{ArticleIDs} ne 'ARRAY';

    my $PlaceholderIDs = join ', ', ('?') x @{ $Param{ArticleIDs} };
    my $Select         = 'SELECT ticket_id, id FROM article WHERE id IN (' . $PlaceholderIDs . ')';

    return if !$DBObject->Prepare(
        SQL  => $Select,
        Bind => [ map{ \$_ }@{ $Param{ArticleIDs} } ],
    );

    my %TicketIDs;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        push @{ $TicketIDs{ $Row[0] } }, $Row[1];
    }

    return %TicketIDs;
}

1;
