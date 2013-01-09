#!/usr/bin/perl

use strict;
use warnings;

use Fcntl;

sub main {
	sleep (100);
	return 1;
}

sub proc_is_running {
	my ($pid) = @_;

	my $proc_name = $0;

	my $proc_pid_file = "/proc/$pid/cmdline";
	open PROC_CMD, '<', $proc_pid_file
	    or return 0;
	my $cmdline_content = <PROC_CMD>;
	close PROC_CMD;

	return 0 if (not defined $cmdline_content);

	chomp $cmdline_content;
	
	return 1
		if $cmdline_content =~ m!^.*perl.*$proc_name.*$!;

	return 0;
}

sub create_pid_file_impl {
    my ($pid_file) = @_;

    print "PID: Openning pid file ($pid_file)\n";
    my $pid_file_handle = sysopen PID_FILE_HANDLE, $pid_file, O_EXCL | O_WRONLY | O_CREAT | O_TRUNC;
    
    if ( $pid_file_handle ) {
        print PID_FILE_HANDLE $$;
        close PID_FILE_HANDLE;
        return 1;
    }

    # check if its empty
    open FP, '<', $pid_file or return 0;
    my $pid = <FP>;
    # file is empty
    if (not defined $pid) {
        close PID_FILE_HANDLE;
	unlink $pid_file;
        return 0;
    }
    # file is not empty
    chomp $pid;

    my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks) = stat FP
         or return 0;

    my $now = time ();
    my $diff = $now - $ctime;
    if ( $diff >= 10 ) {
      my $process_runing = proc_is_running ($pid);
      return 2 if $process_runing;
      # process not running, then delete pidfile and dont grap lock;
      unlink $pid_file;
      return 0;
    }

    return 2;
}

sub create_pid_file {
    my ($pid_file) = @_;

    my $ret = 0;
    print "PID: Try to catch pid lock ($pid_file)\n";
    for (my $p = 0; $p < 5; ++$p) {
    	$ret = create_pid_file_impl ($pid_file);
	return 0 if $ret == 2;
	return 1 if $ret;
    }

    return $ret;
}

my $pid_file_loc = "/tmp/pid";
my $pid_lock = 0;

my $ret = 0;
eval
{
    local $SIG{INT} = sub { die "intk\n" };
    $pid_lock = create_pid_file ($pid_file_loc);
    unless ($pid_lock)
    {
	print "Proc running. Check pid file: $pid_file_loc\n";
	$ret = 0;
    }
    else
    {
    	my $start = time ();
    	$ret = main ();
	my $end = time ();
	my $diff = $end - $start;
	print "Runtime: $diff secs.\n";
    }

    return 1;

} or do {
	my $err = $@;

	# break from keyboard
	if ($err =~ /^intk/ && $pid_lock) {
	    print "unlinking pidfile\n";
	    truncate $pid_file_loc, 0;
	    unlink $pid_file_loc;
	    exit (1);
	}

	if ($err) {
	    print "died with exception: $err\n";
	    goto FALLBACK;
	}

FALLBACK:
	eval {
		local $@;
		return 1;
	} or do {
		my $err = $@;
		if ($err) {
		    print "died with exception: $err\n";
		}
		
	};
};

if ($pid_lock)
{
    print "unlinking pidfile\n";
    truncate $pid_file_loc, 0;
    unlink $pid_file_loc;
}

exit ($ret);