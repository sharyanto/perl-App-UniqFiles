package App::UniqFiles;

use 5.010;
use strict;
use warnings;
use Log::Any qw($log);

use Digest::MD5;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(uniq_files);

# VERSION

our %SPEC;

$SPEC{uniq_files} = {
    summary => 'Report or omit duplicate file contents',
    description => <<'_',

Given a list of filenames, will check each file size and content for duplicate
content. Interface is a bit like the `uniq` Unix command-line program.

_
    args    => {
        files => ['array*' => {
            of         => 'str*',
            arg_pos    => 0,
            arg_greedy => 1,
        }],
        report_unique => [bool => {
            summary => 'Whether to return unique items',
            default => 1,
            arg_aliases => {
                u => {
                    summary => 'Alias for --report-unique --report-duplicate=0',
                    code => sub {
                        my %args = @_;
                        my $args = $args{args};
                        $args->{report_unique}    = 1;
                        $args->{report_duplicate} = 0;
                    },
                },
                d => {
                    summary =>
                        'Alias for --noreport-unique --report-duplicate=1',
                    code => sub {
                        my %args = @_;
                        my $args = $args{args};
                        $args->{report_unique}    = 0;
                        $args->{report_duplicate} = 1;
                    },
                },
            },
        }],
        report_duplicate => [int => {
            summary => 'Whether to return duplicate items',
            description => <<'_',

Can be set to either 0, 1, 2.

If set to 2 (the default), will only return the first of duplicate items. For
example: file1 contains text 'a', file2 'b', file3 'a'. Only file1 will be
returned because file2 is unique and file3 contains 'a' (already represented by
file1).

If set to 1, will return all the the duplicate items. From the above example:
file1 and file3 will be returned.

If set to 0, duplicate items will not be returned.

_
            default => 2,
            arg_aliases => {
            },
        }],
        count => [bool => {
            summary => "Whether to return each file content's ".
                "number of occurence",
            description => <<'_',

1 means the file content is only encountered once (unique), 2 means there is one
duplicate, and so on.

_
            default => 0,
        }],
    },
};
sub uniq_files {
    my %args = @_;

    my $files = $args{files};
    return [400, "Please specify files"] if !$files || !@$files;
    my $report_unique    = $args{report_unique}    // 1;
    my $report_duplicate = $args{report_duplicate} // 2;
    my $count            = $args{count}            // 0;

    # get sizes of all files
    my %size_counts; # key = size, value = number of files having that size
    my %file_sizes; # key = filename, value = file size, for caching stat()
    for my $f (@$files) {
        my @st = stat $f;
        unless (@st) {
            $log->error("Can't stat file `$f`: $!, skipped");
            next;
        }
        $size_counts{$st[7]}++;
        $file_sizes{$f} = $st[7];
    }

    # calculate digest for all files having non-unique sizes
    my %digest_counts; # key = digest, value = num of files having that digest
    my %digest_files; # key = digest, value = [file, ...]
    my %file_digests; # key = filename, value = file digest
    for my $f (@$files) {
        next unless defined $file_sizes{$f};
        next if $size_counts{ $file_sizes{$f} } == 1;
        my $fh;
        unless (open $fh, "<", $f) {
            $log->error("Can't open file `$f`: $!, skipped");
            next;
        }
        my $ctx = Digest::MD5->new;
        $ctx->addfile($fh);
        my $digest = $ctx->hexdigest;
        $digest_counts{$digest}++;
        $digest_files{$digest} //= [];
        push @{$digest_files{$digest}}, $f;
        $file_digests{$f} = $digest;
    }

    my %file_counts; # key = file name, value = num of files having file content
    for my $f (@$files) {
        next unless defined $file_sizes{$f};
        if (!defined($file_digests{$f})) {
            $file_counts{$f} = 1;
        } else {
            $file_counts{$f} = $digest_counts{ $file_digests{$f} };
        }
    }

    if ($count) {
        return [200, "OK", \%file_counts];
    } else {
        #$log->trace("report_duplicate=$report_duplicate");
        my @files;
        for (sort keys %file_counts) {
            if ($file_counts{$_} == 1) {
                #$log->trace("unique file `$_`");
                push @files, $_ if $report_unique;
            } else {
                #$log->trace("duplicate file `$_`");
                if ($report_duplicate == 1) {
                    push @files, $_;
                } elsif ($report_duplicate == 2) {
                    my $digest = $file_digests{$_};
                    push @files, $_ if $_ eq $digest_files{$digest}[0];
                }
            }
        }
        return [200, "OK", \@files];
    }
}

1;
#ABSTRACT: Report or omit duplicate file contents
__END__

=head1 SYNOPSIS

 # See uniq-files script


=head1 DESCRIPTION


=head1 FUNCTIONS

None are exported, but they are exportable.


=head1 TODO

=over 4

=item * Handle symlinks

Provide options on how to handle symlinks: ignore them? Follow? Also, with
return_duplicate=2, we should not use the symlink (because one of the usage of
uniq-files might be to delete duplicate files).

=item * Handle special files (socket, pipe, device)

Ignore them.

=item * Check hardlinks/inodes first

For fast checking.

=item * Arguments hash_skip_bytes & hash_bytes

For only checking uniqueness against parts of contents.

=item * Arguments hash_module/hash_method/hash_sub

For doing custom hashing instead of Digest::MD5.

=back

=cut
