# just to make PodWeaver happy at the moment
package File::Fixer::Examples;

=pod

=head1 DESCRIPTION

This manual presents several examples on how to use File::Fixer.

=head2 A simple case

Check that a file exists and has the correct ownership and permissions:

 my $res = check_file(
   "/etc/myapp/passwords.yaml",
   { exists => 1, owner=>'root', group=>'root', mode => 'go-a' },
 );
 die $res->{message} unless $res->{success};

If the file doesn't exist, or exists but is a directory, or doesn't have the
correct ownership/permissions, the above code will die.

If we set fix flag to true:

 my $res = check_file(
   "/etc/myapp/passwords.yaml",
   { exists => 1, owner=>'root', group=>'root', mode => 'go-a' },
   1,
 );
 die $res->{message} unless $res->{success};

Then check_file() will try to fix every failed clause instead of just giving up.
If the file doesn't exist (exists=>1 fails), an attempt is made to create it. If
the path is a directory, an attempt is made to delete the directory and then
create the file.

=head2 Specifying file content

 # mail to root and postmaster goes to black hole
 check_file(
   "/var/qmail/alias/.qmail-root",
   {
     exists  => 1,
     owner   => qr/^(root|alias)$/,
     group   => ['root', 'alias'],
     mode    => 0644,
     content => "#",
   },
   1
 );

The above code will make sure that the .qmail-root file exists with the correct
ownership (must be owned by root or alias user), mode, and content as well. If
the file already exists but with different content, it will be rewritten with
the specified wanted content.

Note also that you can provide a Regexp object or array for owner/group.

=head2 Specifying default content for newly created file

Continuing from the previous example, if you only want to provide a content for
newly created file and not change existing file content, you can use
B<new_content>:

 check_file(
   "/var/qmail/alias/.qmail-root",
   {
     exists      => 1,
     owner       => qr/^(root|alias)$/,
     group       => ['root', 'alias'],
     mode        => 0644,
     new_content => "#",
   },
   1
 );

=head2 Checking directory

When checking a directory, you have an option to recursively check
files/subdirectories.

 check_dir(
   "/etc/spanel",
   {
     exists        => 1,
     owner         => 'root', group => 'root', mode => 'go-w',
     entries_re    => {
       # all entries inside /etc/spanel must all be owned by root
       '.*' => { owner=>'root', group=>'root' },
     },
   },
   1
 );

There are also the variants: B<entries>, B<entries_re_recursive',
B<all_entries>, B<all_entries_re>, B<all_entries_re_recursive>

=head2 More detailed fixing flags

Instead of trying to fix everything, you might want to choose only to fix some
stuffs only.

=cut

