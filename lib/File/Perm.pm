package File::Fixer;
# ABSTRACT: Check and fix files (permission, ownership, content, and so on)

use 5.010;
use strict;
use warnings;
use Log::Any '$log';
require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(check_file);

# these clauses are handled by _check_file itself (for performance/convenience)
# instead of delegating to cfclause_*(). they will
my @builtin_clauses = qw(
                            precheck postcheck
                            is_dir is_file is_symlink
                            exists mkdir_p
                            owner group mode
                    );

sub _check_file($$;$) {
    my ($path, $clauses, $fix_flag) = @_;

    die "Missing required argument: path\n"
        unless defined($path);

    # check clauses
    my @clauses; # ([name, value, meta], ...)
    for my $cname (keys %clauses) {
        my $meth = "cf_$cname";
        die "Unknown check_file clause: $cname\n"
            unless __PACKAGE__->can($meth);
        my $mmeth = "cfmeta_$cname";
        my $meta = __PACKAGE__->can($mmeth) ?
            __PACKAGE__->$mmeth : {};
        $meta->{prio} //= 50;
        push @clauses, {
            name=>$cname, sub=>\&$meth,
            value=>$clauses{$cname}, meta=>$meta};
    }

    # sort by priority
    @clauses = sort {$a->{meta}{prio}<=>$b->{meta}{prio}} @clauses;

    for my $c (@clauses) {
        next unless defined($c->{value});
        $log->tracef("Calling cf_$c->{name}(%s) ...", $c->{value});
        my $res = $c->{sub}->(%$c, path=>$path);
    }
}

sub check_file {
    my ($path, $clauses, $fix_flag) = @_;
    $log->trace("-> check_file($path, ...)");
    $clauses->{is_file} //= 1;
    my $res = _check_file($path, $clauses, $fix_flag);
    $log->tracef("<- check_file(), res=%s", $res);
    $res;
}

sub check_dir {
    my ($path, $clauses, $fix_flag) = @_;
    $log->trace("-> check_dir($path, ...)");
    $clauses->{is_dir} //= 1;
    my $res = _check_file($path, $clauses, $fix_flag);
    $log->tracef("<- check_dir(), res=%s", $res);
    $res;
}

sub check_symlink {
    my ($path, $clauses, $fix_flag) = @_;
    $log->trace("-> check_symlink($path, ...)");
    $clauses->{is_symlink} //= 1;
    my $res = _check_file_or_dir($path, $clauses, $fix_flag);
    $log->tracef("<- check_symlink(), res=%s", $res);
    $res;
}

#                            content content_r
#                            files files_r
#                            dirs dirs_r

1;
__END__

=head1 SYNOPSIS

 use File::Fixer qw(check_file check_dir check_symlink);

 # check password file
 my $res = check_file(
   "/etc/myapp/passwords.yaml",
   {
     exists      => 1,      # must exist
     mode        => 'go-a', # must not be readable by group/other
     owner       => 'root', # must be owned by root
     group       => 0,      # group must be root also (numeric version)
   },
   1,  # fix flag, a true scalar value means fix everything
 );
 die $res->{message} unless $res->{success};

 # create/fix hosting account structure:
 #
 # /home/accounts/ACCID/  (root    , root , 0755)
 #   home/                (ACCID   , ACCID, 0700), files inside owned by ACCID
 #   sites/               (root    , ACCID, 0751), must only contain dirs
 #     SITENAME/          (www-data, ACCID, 0550)
 #       www/             (ACCID   , ACCID, 0755)
 #         ...              files inside must be owned by ACCID or "cgi-ACCID",
 #                          *.cgi or *.pl files must be +x.
 #       ssl/             (ACCID   , ACCID, 0755)
 #       etc/             (ACCID   , ACCID, 0755)
 #       sysetc/          (root    , ACCID, 0755)
 #       syslog/          (root    , ACCID, 0750)
 #    ...
 #   public/              (ACCID   , ACCID, 0755)
 #   sysetc/              (root    , ACCID, 0750)
 #   syslog/              (root    , ACCID, 0750)

 sub fixperm {
   my ($acc) = @_;

   my $spec_docroot = {
     is_dir  => 1,
     exists  => 1,
     owner   => $acc, group => $acc, mode => 0755,
     all_entries => {
       '.*' => { owner => [$acc, "cgi-$acc"] },
     },
     files_match_r   => {
       '\.(cgi|pl)$' => { mode => '+x' },
     },
   };

   my $res = check_dir(
     "/home/accounts/$acc",
     {
       exists      => 1,
       owner       => 'root', group => 'root', mode => 0755,
       content     => {
         home    => {
           is_dir   => 1, exists => 1,
           owner    => $acc, group => $acc, mode => 0700,
           content_match_r => {
             '.*' => { owner => $acc }
           },
         },
         sites   => {
           is_dir   => 1, exists => 1,
           owner    => 'root', group => $acc, mode => 0751,
           all_content_match => {
             '.*' => {
               is_dir  => 1,
               owner   =>
               content => {
                 www    => $spec_docroot,
                 ssl    => $spec_docroot,
                 etc    => { is_dir=>1, exists=>1, mode => 0755,
                             owner => $acc, group => $acc, },
                 sysetc => { is_dir=>1, exists=>1, mode => 0755,
                             owner => 'root', group => $acc, },
                 syslog => { is_dir=>1, exists=>1, mode => 0750,
                             owner => 'root', group => $acc, },
               },
             },
           },
         },
         public  => { is_dir=>1, exists=>1,
                      owner=>$acc, group=>$acc, mode=>0755, },
         sysetc  => { is_dir=>1, exists=>1,
                      owner=>'root', group=>$acc, mode=>0750, },
         syslog  => { is_dir=>1, exists=>1,
                      owner=>'root', group=>$acc, mode=>0750, },
       },
     },

     1, # fix flag, a true scalar value means fix everything
   );
   die $res->{message} unless $res->{success};
 );


=head1 DESCRIPTION

This module lets you specify various desired criteria of files/directories
declaratively, sort of like a schema for filesystem. You can check (and
optionally fix) files/directories against this schema.

=head1 FUNCTIONS

None of the functions are exported by default.

=head2 check_file($path, \%clauses[, $fix_flag])

=head2 check_dir($path, \%clauses[, $fix_flag])

=head2 check_symlink($path, \%clauses[, $fix_flag])

These functions all call _check_file() internally. check_file() is equivalent
to:

 $clauses->{is_file} //= 1;
 _check_file($path, $clauses, $fix_flag);

check_dir() is equivalent to:

 $clauses->{is_file} //= 1;
 _check_file($path, $clauses, $fix_flag);

check_symlink() is equivalent to:

 $clauses->{is_symlink} //= 1;
 _check_file($path, $clauses, $fix_flag);

_check_file() checks a file/dir/symlink against one or more criteria and returns
the check result. It accepts path name, a hash of clauses (each specifying a
criteria), and a fix flag.

First _check_file() performs an C<lstat> on path (plus an extra C<stat> if the
path is a symlink). It then evaluate each clause handler on a certain order. If
an unknown clause is given, the function dies.

If fix flag is false: When a clause check fails (e.g. exists=>1 clause given
when the file doesn't exist, or mode=>0755 when file's permission mode is 0644),
the function will return {success=>0, path=><corresponding path>, clause=><the
failing clause, e.g. 'exists' or 'mode'>, message=><error message>}.

If fix flag is true: When a clause check fails, it will try to fix the situation
and continue to the next clause. When the situation cannot be fixed, the
function returns failure result as above (unless when you tell _check_file() to
ignore errors, see L<Fix flag>).

If all clauses succeed, the function will return {success=>1}.


=head2 Clauses

Below is the list of known clauses, in the order of evalution:

=over 4

=back

=head2 Fix flag

Fix flag can be a scalar false value, which means no fixing should be done, or a
scalar true value, which means try to fix everything and fails on the first
fixing failure.

Fix flag can can be hash reference to toggle fixing/not-fixing on specific
clauses. The hash should contain clause names or special keys 'ALL' and
'IGNORE_ERRORS'. example:

 {
   mode  => 1,      # only fix mode and ownership, don't try to fix anything
   owner => 1,      # else.
 }

Another example:

 {
   ALL           => 1, # try to fix everything, but ...
   exists        => 0, # if a file doesn't exist, don't try to create it, or
                       # if a file exists when it should not, don't delete it

   IGNORE_ERRORS => 1, # ignore errors happening during
 }

Fix flag can also be a code reference. The code will be called with this
arguments: XXX.

In hash form, each pair value of hash can also be a code reference. XXX.

=head1 CUSTOM CLAUSE

Aside from the built-in clauses, you can add your own. To do that, add these
subroutines to the File::Fixer package: cfmeta_<NAME>, cfcheck_<NAME>, and
cffix_<NAME>. For example:

 # specify priority for the clause, default is 50
 sub cfmeta_name_case { { prio=>10 } }

 # implement checking. $name is clause name, $value is clause value, and $ctx is
 # an object containing extra data, e.g. $context->clauses().
 sub cfcheck_name_case {
   my ($path, $name, $value, $ctx) = @_;
   next unless defined $value;

   if ($value eq 'lower') {
     return $path eq lc($path);
   } elsif ($value eq 'upper') {
     return $path eq uc($path);
   } else {
     die "Invalid value for 'name_case' clause: $value\n";
   }
 }

 # implement fixing, only called if fixing needs to be done
 sub cffix_name_case {
   my ($path, $name, $value, $ctx) = @_;

   # rename() will return true/false
   rename $path, ($value eq 'lower' ? lc($path) : uc($path));
 }


=head1 HISTORY

The idea for this module came out in 2006 as part of the Spanel hosting control
panel project. First public release of this module is in Feb 2011.


=head1 SEE ALSO

L<File::Fixer::Examples> for more examples.

=cut
