# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::User::APIKey;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Object);

use Bugzilla::User;
use Bugzilla::Util qw(generate_random_password trim);
use Bugzilla::Error;

#####################################################################
# Overridden Constants that are used as methods
#####################################################################

use constant DB_TABLE   => 'user_api_keys';
use constant DB_COLUMNS => qw(
  id
  user_id
  api_key
  app_id
  description
  revoked
  creation_ts
  last_used
  last_used_ip
  sticky
);

use constant UPDATE_COLUMNS => qw(description revoked last_used last_used_ip sticky);
use constant VALIDATORS     => {
  api_key     => \&_check_api_key,
  app_id      => \&_check_app_id,
  description => \&_check_description,
  revoked     => \&Bugzilla::Object::check_boolean,
  sticky      => \&Bugzilla::Object::check_boolean,
};
use constant LIST_ORDER => 'id';
use constant NAME_FIELD => 'api_key';

# Exclude these objects from memcached
use constant USE_MEMCACHED => 0;

# Accessors
sub id           { return $_[0]->{id} }
sub user_id      { return $_[0]->{user_id} }
sub api_key      { return $_[0]->{api_key} }
sub app_id       { return $_[0]->{app_id} }
sub description  { return $_[0]->{description} }
sub revoked      { return $_[0]->{revoked} }
sub creation_ts  { return $_[0]->{creation_ts} }
sub last_used    { return $_[0]->{last_used} }
sub last_used_ip { return $_[0]->{last_used_ip} }
sub sticky       { return $_[0]->{sticky} }

# Helpers
sub user {
  my $self = shift;
  $self->{user} //= Bugzilla::User->new({name => $self->user_id, cache => 1});
  return $self->{user};
}

sub update_last_used {
  my ($self, $remote_ip) = @_;
  my $timestamp = Bugzilla->dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
  $self->set('last_used',    $timestamp);
  $self->set('last_used_ip', $remote_ip);
  $self->update;
}

# We override Object.pm audit_log cause we need to remove the
# last_used and last_used_ip changes so they are not logged.
# Otherwise the audit_log table would fill up from people just
# normally using the api keys.
sub audit_log {
  my ($self, $changes) = @_;
  # Only interested in AUDIT_UPDATE
  if (ref $changes eq 'HASH') {
    delete $changes->{last_used};
    delete $changes->{last_used_ip};
  }
  $self->SUPER::audit_log($changes);
}

# Setters
sub set_description { $_[0]->set('description', $_[1]); }
sub set_revoked     { $_[0]->set('revoked',     $_[1]); }
sub set_sticky      { $_[0]->set('sticky',      $_[1]); }

# Validators
sub run_create_validators {
  my ($class, $params) = @_;
  $params = $class->SUPER::run_create_validators($params);
  $params->{creation_ts}
    ||= Bugzilla->dbh->selectrow_array('SELECT LOCALTIMESTAMP(0)');
  return $params;
}

sub _check_api_key { return generate_random_password(40); }
sub _check_description { return trim($_[1]) || ''; }

sub _check_app_id {
  my ($invocant, $app_id) = @_;

  ThrowCodeError("invalid_app_id", {app_id => $app_id})
    unless $app_id =~ /^[[:xdigit:]]+$/;

  return $app_id;
}

sub create_special {
  my ($class, @args) = @_;
  local VALIDATORS->{api_key} = sub { return $_[1] };
  return $class->create(@args);
}
1;

__END__

=head1 NAME

Bugzilla::User::APIKey - Model for an api key belonging to a user.

=head1 SYNOPSIS

  use Bugzilla::User::APIKey;

  my $api_key = Bugzilla::User::APIKey->new($id);
  my $api_key = Bugzilla::User::APIKey->new({ name => $api_key });

  # Class Functions
  $user_api_key = Bugzilla::User::APIKey->create({
      description => $description,
  });

=head1 DESCRIPTION

This package handles Bugzilla User::APIKey.

C<Bugzilla::User::APIKey> is an implementation of L<Bugzilla::Object>, and
thus provides all the methods of L<Bugzilla::Object> in addition to the methods
listed below.

=head1 METHODS

=head2 Accessor Methods

=over

=item C<id>

The internal id of the api key.

=item C<user>

The Bugzilla::User object that this api key belongs to.

=item C<user_id>

The user id that this api key belongs to.

=item C<api_key>

The API key, which is a random string.

=item C<description>

An optional string that lets the user describe what a key is used for.
For example: "Dashboard key", "Application X key".

=item C<revoked>

If true, this api key cannot be used.

=item C<last_used>

The date that this key was last used. undef if never used.

=item C<update_last_used>

Updates the last used value to the current timestamp. This is updated even
if the RPC call resulted in an error. It is not updated when the description
or the revoked flag is changed.

=item C<set_description>

Sets the new description

=item C<set_revoked>

Sets the revoked flag

=back
