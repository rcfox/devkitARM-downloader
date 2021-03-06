#!/usr/bin/perl
use strict;
use warnings;
use Cwd;
use LWP::Simple;
use Config::INI::Reader;
use Archive::Tar;
use Parallel::ForkManager;

my $max_procs = $ARGV[0] || 10;
my $pm = new Parallel::ForkManager($max_procs);

# Used to figure out which files to get, based on the user's OS
my $original_extension = '.exe';
my $new_extension = '.tar.bz2';
my $os = lc($^O);
if ($os eq 'linux')
{
    my $arch = `uname -m`; chomp($arch);
    $os = $arch.'-'.$os;
}
elsif ($os eq 'darwin')
{
    $os = 'osx';
}
elsif ($os eq 'mswin32' || $os eq 'cygwin')
{
    $os = 'win32';
    $new_extension = '.exe';
}
else
{
    die "There are no libnds binaries available for your operating system.\n";
}

# Parse the INI file into a hash
my $ini = get('http://devkitpro.sourceforge.net/devkitProUpdate.ini') or die "Unable to access the devkitPro website.\n";
$ini =~ s/win32/$os/g;
$ini =~ s/$original_extension/$new_extension/g;
my %ini_hash = %{Config::INI::Reader->read_string($ini)};

# Files to download for NDS development
# Note: The script currently depends on devkitARM and ndsexamples being first and second in this array.
my %files =
    (
     'devkitARM' => [],
     'ndsexamples' => ['examples','ds'],
     'libnds' => ['libnds'],
     'libndsfat' => ['libnds'],
     'maxmodds' => ['libnds'],
     'dswifi' => ['libnds'],
     'defaultarm7' => ['libnds'],
     'filesystem' => ['libnds'],
    );

# Base URL for all files
my $download_base = $ini_hash{devkitProUpdate}{URL};

mkdir 'examples';
mkdir 'examples/ds';
mkdir 'libnds';

# Download each file
foreach(keys %files)
{    
    $pm->start and next;
    
    print "Downloading $_ v$ini_hash{$_}{Version}...\n";
    my $file = $ini_hash{$_}{File};
    my $url = "$download_base/$file";
    mirror($url,$file) or die $!;
    print "Finished downloading $_ v$ini_hash{$_}{Version}.\n";

    my $file_prefix = "";
    my $f = $ini_hash{$_}{File};
    print "Extracting $f...\n";
    map { chdir "$_"; $file_prefix .= "../" } @{$files{$_}};
    Archive::Tar->extract_archive($file_prefix."$f",1);
    map { chdir '..' } @{$files{$_}};
    print "Finished extracting $f...\n";
    
    $pm->finish;
}
$pm->wait_all_children;

# Either set up the user's environment variables, or tell him to do so.
my $current_dir = getcwd;
if ($os eq 'win32' && 0) # The && 0 part will cause this to fail, until I figure out the registry stuff.
{
# Add DEVKITPRO and DEVKITARM environment variables to the registry, using the module found here:
# http://search.cpan.org/perldoc?Win32::TieRegistry
# The values go in HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment
# From http://msdn.microsoft.com/en-us/library/ms682653%28VS.85%29.aspx
# (Ew, MSDN. I feel dirty!)
}
elsif ($ENV{SHELL} =~ /bash/)
{
    my $home = $ENV{HOME};
    
    print "\nAdding environment variables to $home/.bashrc:\n";
    print "  export DEVKITPRO=$current_dir\n";
    print "  export DEVKITARM=\$DEVKITPRO/devkitARM\n";

    open my $bashrc, ">>$home/.bashrc" or die $!;
    print $bashrc "export DEVKITPRO=$current_dir\n";
    print $bashrc "export DEVKITARM=\$DEVKITPRO/devkitARM\n";
    close $bashrc;
}
else
{
    print "\nPlease set up the following environment variables for your shell:\n";
    print "  DEVKITPRO=$current_dir\n";
    print "  DEVKITARM=\$DEVKITPRO/devkitARM\n";
}
