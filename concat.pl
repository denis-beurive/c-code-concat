#!/usr/bin/perl
#
# perl concat.pl --verbose --src=../src --reject-dir=../src/examples --reject-dir=../src/tests --reject-file=../src/files_com.c --reject-file=../src/files_com.h  --dest=../src --target=files_com

use strict;
use warnings FATAL => 'all';
use File::Spec::Functions qw(catfile rel2abs);
use Getopt::Long;
use Data::Dumper;

use constant K_FILES => 'files';
use constant K_DIRECTORIES => 'directories';
use constant DEFAULT_DESTINATION => '.';
use constant TARGET_BASENAME => 'concat';

# Print an error message and exit.
# @param $in_message The message to print.

sub error {
    my ($in_message) = @_;
    printf("ERROR: %s\n", $in_message);
    exit(1);
}

# Print a warning message and exit.
# @param $in_message The message to print.

sub warning {
    my ($in_message) = @_;
    printf("WARNING: %s\n", $in_message);
}

sub build_title {
    my ($in_label) = @_;
    my $title = sprintf('%s [INCLUDED] %s %s', '#' x 10, $in_label, '#' x 10);
    my $line = sprintf("%s", '#' x length($title));
    return(sprintf("// %s\n// %s\n// %s", $line, $title, $line));
}

sub array_max_string_length {
    my @sorted = sort (map { length($_) } @_);
    return(pop(@sorted));
}



# Load a C/H file and returns the list of included H files found in this file.
# @param $in_path Path to the C/H file.
# @param $out_code Reference to an array that is used to store the lines of C code.
#        NOTE: the C/H coded is striped of its "#include" statements.
# @return A reference to an array that contains 3 elements:
#         - a rank value, that may be undefined (value `undef`).
#           The rank should only (optionally) be used within H files.
#           First line of the H file must be: "// RANK=<rank value>" (ex: "// RANK=10")
#         - a flag that tells whether the (H) file must be exposed or not.
#           value "0:0": the (H) file must not be exposed.
#           value "1:<rank value>": the (H) file must not not be exposed.
#           First line of the H file must be: "// EXPOSE <rank value>" (ex: "// EXPOSE 10")
#         - a reference to an array that contains the included files striped from the input file.
#           ex: [ '<stdio.h>', '"local_file.h"' ]

sub load_code {
    my ($in_path, $out_code) = @_;
    my $fd;
    my $rank = undef;
    my $expose = '0:0';
    my @result;

    @{$out_code} = ( sprintf("\n%s\n\n", build_title($in_path)) );
    open($fd, '<', $in_path) or return(undef);
    my @lines = <$fd>;
    close($fd);

    if ($lines[0] =~ s/^\s*\/\/\/*\s*RANK\s*=\s*(\d+)\s*$//) {
        $rank = $1;
    } elsif ($lines[0] =~ s/^\s*\/\/\/*\s*EXPOSE\s+(\d+)\s*$//) {
        $expose = "1:$1";
    }

    my @includes = ();
    foreach my $line (@lines) {
        if ($line =~ m/^#include\s+(<|")([^">]+)("|>)(\s*\/\/\/*\s*PRECEDED\s+BY\s*:\s*(.*))?/) {
            if (defined($4)) {
                push(@includes, ">${5}")
            }
            push(@includes, "${1}${2}${3}");
        } else {
            push(@{$out_code}, $line);
        }
    }
    push(@{$out_code}, sprintf("\n\n// end of \"%s\"\n\n", $in_path));
    @result = ($rank, $expose, \@includes);
    return \@result;
}

# Write a code into a file.
# @param $in_path Path to the file.
# @param $in_code The code to write.
# @return On success: 1. On failure: 0.

sub write_code {
    my ($in_path, $in_code) = @_;
    my $fd;

    printf("W [%s]\n", $in_path);
    open($fd, '>', $in_path) or return(0);
    print $fd $in_code;
    close($fd);
    return(1);
}

# List the content of a directory.
# @param $in_path The path to the directory to list.
# @return On success, a reference to a hash that contains 2 keys:
#         - 'files' (or `&K_FILES`) => a reference to an array of absolute paths to files.
#         - 'directories' (or `&K_DIRECTORIES`) => a reference to an array of absolute paths to (sub)directories.
#         On failure: undef.

sub ls {
    my ($in_path) = @_;
    my $dh;
    my @files = ();
    my @directories = ();

    $in_path = rel2abs($in_path);

    opendir $dh, $in_path or return(undef);
    while (readdir $dh) {
        next if ('.' eq $_) || ('..' eq $_);
        my $entry_absolute_path = catfile($in_path, $_);
        if (-f $entry_absolute_path) { push(@files, rel2abs($entry_absolute_path)) }
        elsif (-d $entry_absolute_path) { push(@directories, rel2abs($entry_absolute_path)) }
    }
    closedir $dh;

    return({
        &K_FILES       => \@files,
        &K_DIRECTORIES => \@directories
    })
}

# List the content of a directory, recursively.
# @param $in_path The path of the directory to list.
# @param %options:
#        - 'file_filter': reference to a function used to decide whether a file should be kept ot not.
#          The function's signature is: `sub function { my ($file_path) = @_; ... return $status }`
#                                       - if `$status` is non-null, then the file is kept.
#                                       - if `$status` is null, then the file is not kept.
#          Example: `sub my_file_filter { return shift =~ m/\.c$/; }`
#                   Keep only the files whose names end with the suffix ".c".
#        - 'file_directory': reference to a function used to decide whether a directory should be kept ot not.
#          The function's signature is: `sub function { my ($directory_path) = @_; ... return $status }`
#                                       - if `$status` is non-null, then the directory is kept.
#                                       - if `$status` is null, then the directory is not kept.
#                                         And all files within this directory are rejected (as well),
#                                         but not the subdirectories. The subdirectories will be visited (but
#                                         not necessarily kept - depending on the filtration status).
#          Example: `sub my_directory_filter { return ! (shift =~ m/examples$/); }`
#                   Reject all directories whose associated paths end with the string "examples".
#                   Keep all other directories.
# @return A reference to a hash which keys are absolute paths to directories.
#         And values are references to arrays that contain lists of absolute files paths.
#         That is:  { '/path/to/dir1' => ['/path/to.file1',...],
#                     '/path/to/dir2' => ['/path/to.file1',...],
#                     ... }
# @note All paths returned by this function are *absolute real* paths.

sub find {
    my ($in_path, %options) = @_;
    my @s_stack = ();
    my %files = ();
    my $filter_file = exists($options{'file_filter'}) ? $options{'file_filter'} : undef;
    my $filter_directory = exists($options{'directory_filter'}) ? $options{'directory_filter'} : sub {return 1};

    $in_path = rel2abs($in_path);
    push(@s_stack, $in_path);

    while(int(@s_stack) > 0) {
        my $current_dir = pop(@s_stack);
        my $entries = ls($current_dir);

        if ($filter_directory->($current_dir)) {
            my @current_dir_files = @{$entries->{&K_FILES}};
            my $files = \@current_dir_files;

            if (defined($filter_file)) {
                my @filtered = ();
                foreach my $file (@current_dir_files) {
                    push(@filtered, $file) if $filter_file->($file);
                    $files = \@filtered;
                }
            }

            $files{$current_dir} = $files;
        }

        push(@s_stack, @{$entries->{&K_DIRECTORIES}});
    }

    return \%files;
}

# Takes as input the result of the function `find`, and keep only the files names.
# @param $in_find_result The result of the function `find`.
# @return An array of absolute real paths to files.

sub to_file_list {
    my ($in_find_result) = @_;
    my @result = ();

    foreach my $dir (keys %{$in_find_result}) {
        push(@result, @{$in_find_result->{$dir}})
    }
    return(@result);
}

sub test_load_code {
    my @code;
    my $data = load_code('src/sftp_api.h', \@code);
    my $rank = $data->[0];
    my $expose = $data->[1];
    my @includes = @{$data->[2]};
    printf("rank:   %s\n", defined($rank) ? $rank : "undef");
    printf("expose: %s\n", $expose);
    printf("\n%s\n", join('', @includes));
    printf("\n%s\n", join('', @code));
}

# test_load_code();
# exit 0;

my %REJECT_DIR = ();
my %REJECT_FILE = ();
my @C_FILES = ();
my @H_FILES = ();

# Parse the command line.
my @cli_src;
my @cli_reject_dir;
my @cli_reject_file;
my $cli_verbose;
my $cli_destination;
my $cli_target;

if (! GetOptions (
    'src=s'         => \@cli_src,
    'reject-dir=s'  => \@cli_reject_dir,
    'reject-file=s' => \@cli_reject_file,
    'dest=s'        => \$cli_destination,
    'target=s'      => \$cli_target,
    'verbose'       => \$cli_verbose)) {
    error("invalid command line");
}
$cli_verbose = defined($cli_verbose) ? 1 : 0;
$cli_target = defined($cli_target) ? $cli_target : &TARGET_BASENAME;
$cli_destination = rel2abs(defined($cli_destination) ? $cli_destination : &DEFAULT_DESTINATION);

error('Option --src is missing') if (int(@cli_src) == 0);

if (0 != $cli_verbose) {
    print("source:\n");
    foreach my $dir (@cli_src) { printf("   - \"%s\"\n", $dir) }
    if (int(@cli_reject_dir) > 0) {
        print("reject:\n");
        foreach my $dir (@cli_reject_dir) { printf("   - \"%s\"\n", $dir) }
    }
    printf("destination: \"%s\"\n", $cli_destination);
    printf("target: \"%s\"\n", $cli_target);
}

# Select the files to concatenate.
%REJECT_DIR = map { rel2abs($_) => undef } @cli_reject_dir;
%REJECT_FILE = map { rel2abs($_) => undef } @cli_reject_file;
sub my_directory_filter {
    my $p = shift();
    return ! exists($REJECT_DIR{$p}) }
sub my_c_file_filter {
    my $p = shift();
    return 0 if exists($REJECT_FILE{$p});
    return $p =~ m/\.c$/; }
sub my_h_file_filter {
    my $p = shift();
    return 0 if exists($REJECT_FILE{$p});
    return $p =~ m/\.h$/; }

foreach my $src (@cli_src) {
    # Select the C files to concatenate.
    my $c_files = find($src, 'file_filter' => \&my_c_file_filter, 'directory_filter' => \&my_directory_filter);
    # Select the H files to concatenate.
    my $h_files = find($src, 'file_filter' => \&my_h_file_filter, 'directory_filter' => \&my_directory_filter);

    push(@C_FILES, to_file_list($c_files));
    push(@H_FILES, to_file_list($h_files));
}
@C_FILES = sort @C_FILES;
@H_FILES = sort @H_FILES;

my @C_LINES = ();           # all the lines of code extracted from the C files (excluding the "#include" statements)
my %H_RANKED_LINES = ();    # all the lines of code extracted from the ranked H files (excluding the "#include" statements)
my @H_UNRANKED_LINES = ();  # all the lines of code extracted from the unranked H files (excluding the "#include" statements)
my %H_EXPOSED_LINES = ();   # all the lines of code extracted from the exposed H files (excluding the "#include" statements)

my %C_INCLUDES = ();           # all the "#include" statements extracted from the C files
my %H_RANKED_INCLUDES = ();    # all the "#include" statements extracted from the (non-exposed) ranked H files
my %H_UNRANKED_INCLUDES = ();  # all the "#include" statements extracted from the (non-exposed) unranked H files
my %H_EXPOSED_INCLUDES = ();   # all the "#include" statements extracted from the exposed (ranked) H files

my $max_len;

# Load the H files.
print("Load H files:\n");
$max_len = array_max_string_length(@H_FILES);
foreach my $path (@H_FILES) {
    my @code;
    my $data = load_code($path, \@code);
    error(sprintf('cannot load the file "%s": %s', $path, $!)) if (! defined($data));

    my ($rank, $exposed, $include_lines) = @{$data};
    printf("  %-${max_len}s -> %-5s : %s : %4d (#include statements)\n", $path, defined($rank) ? $rank : "undef" , $exposed, int(@{$include_lines})) if (1 == $cli_verbose);

    # All the lines of code extracted from the ranked H files (excluding the "#include statements")
    if (defined($rank)) {
        error(sprintf('duplicated rank number %d (found in "%s" - and another H file)', $rank, $path)) if (exists($H_RANKED_LINES{$rank}));
        $H_RANKED_LINES{$rank} = \@code;
        foreach my $h (@{$include_lines}) { $H_RANKED_INCLUDES{$h} = undef; }
        next;
    }

    # All the lines of code extracted from the exposed H files (excluding the "#include statements")
    if ($exposed =~ m/^1:(\d+)$/) {
        my $rank = $1;
        error('duplicated rank number %d for exposed H file (found in "%s" - and another H file)', $rank, $path) if exists($H_EXPOSED_LINES{$rank});
        $H_EXPOSED_LINES{$rank} = \@code;
        foreach my $h (@{$include_lines}) { $H_EXPOSED_INCLUDES{$h} = undef; }
        next;
    }

    # All the lines of code extracted from the unranked H files (excluding the "#include statements")
    push(@H_UNRANKED_LINES, @code);
    foreach my $h (@{$include_lines}) { $H_UNRANKED_INCLUDES{$h} = undef; }
}

# Load the C files.
print("Load C files:\n");
$max_len = array_max_string_length(@C_FILES);
foreach my $path (@C_FILES) {
    my @code;
    my $data = load_code($path, \@code);
    error(sprintf('cannot load the file "%s": %s', $path, $!)) if (! defined($data));

    my ($rank, $exposed, $include_lines) = @{$data};
    printf("  %-${max_len}s -> %-5s : %s : %4d (#include statements)\n", $path, defined($rank) ? $rank : "undef" , $exposed, int(@{$include_lines})) if (1 == $cli_verbose);

    warning(sprintf('C (.c) files should not define RANK (found in "%s")', $path)) if (defined($rank));
    warning(sprintf('C (.c) files should not define EXPOSE (found in "%s")', $path)) if ($exposed =~ m/^1:/);
    push(@C_LINES, @code);
    foreach my $h (@{$include_lines}) { $C_INCLUDES{$h} = undef; }
}


my @lines;
my @ranks;
my $output_file;
my @includes;
my @before_includes;

# ====================================================================================
# Concatenate the H exposed files.
# (1) the "#include" statements (for all H exposed files).
# (2) the exposed H exposed files.
# ====================================================================================

@lines = ();

# (1) the "#include" statements (for all H exposed files).
@includes = map { sprintf("%s#include %s\n", $_ =~ m/"/ ? '// ' : '', $_) } sort keys %H_EXPOSED_INCLUDES;
push(@lines, @includes, '', '');

# (2) the exposed H exposed files.
@ranks = sort { $a <=> $b } keys %H_EXPOSED_LINES;
foreach my $rank (@ranks) {
    printf("Add H exposed rank %d\n", $rank);
    push(@lines, sprintf("\n/* --- [exposed header file - rank %d] --- */\n\n", $rank));
    push(@lines, @{ $H_EXPOSED_LINES{$rank} });
    push(@lines, sprintf("\n/* --- [end of exposed header file - rank %d] --- */\n\n", $rank));
}

$output_file = catfile($cli_destination, $cli_target . '.h');
error('cannot write H file "%s": %s', $output_file) if 0 == write_code($output_file, join('', @lines));

# ====================================================================================
# Concatenate the C files (start with H files, then add C files).
# (1) the "#include" statements (for the H files and the C files).
# (2) the (non-exposed) ranked H files (which inclusion order matters).
# (3) the (non-exposed) unranked H files (which inclusion order does not matter).
# (4) the C codes.
# ====================================================================================

@lines = ();

# (1) the "#include" statements (for the H files and the C files).
my %all_include = (%C_INCLUDES, %H_UNRANKED_INCLUDES, %H_RANKED_INCLUDES);
@includes = ();
@before_includes = ();
foreach my $line (sort keys %all_include) {
    if ($line =~ m/^>(.+)$/) {
        # We found a statement that must precede an "#include" statement.
        push(@before_includes, "${1}\n");
    } else {
        push(@includes, sprintf("%s#include %s\n", $line =~ m/"/ ? '// ' : '', $line));
    }
}

# @includes = map { $r = sprintf("%s#include %s\n", $_ =~ m/"/ ? '// ' : '', $_) } sort keys %all_include;
push(@lines, @before_includes, @includes);

push(@lines, sprintf('#include "%s.h"', $cli_target), '', '');

# (2) the (non-exposed) ranked H files (which inclusion order matters).
@ranks = sort { $a <=> $b } keys %H_RANKED_LINES;
foreach my $rank (@ranks) {
    printf("Add H un-exposed ranked %d\n", $rank);
    push(@lines, sprintf("\n/* --- [ranked header file - %d] --- */\n\n", $rank));
    push(@lines, @{ $H_RANKED_LINES{$rank} });
    push(@lines, sprintf("\n/* --- [end of ranked header file - %d] --- */\n\n", $rank));
}

# (3) the (non-exposed) unranked H files (which inclusion order does not matter).
push(@lines, "\n/* --- [unranked header files] --- */\n\n");
push(@lines, @H_UNRANKED_LINES);
push(@lines, "\n/* --- [end of unranked header files] --- */\n\n");

# (4) the C codes.
push(@lines, "\n/* --- [C files] --- */\n\n");
push(@lines, @C_LINES);
push(@lines, "\n/* --- [end of C files] --- */\n\n");

$output_file = catfile($cli_destination, $cli_target . '.c');
error('cannot write C file "%s": %s', $output_file) if 0 == write_code($output_file, join('', @lines));




