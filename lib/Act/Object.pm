package Act::Object;
use Act::Config;

=head1 NAME

Act::Object - A base object for Act objects

=head1 SYNOPSIS


=head1 DESCRIPTION

=head2 Methods

The Act::Object class implements the following methods:

=over 4

=item new( %args )

The constructor returns an existing Act::Object object, given 
enough parameters to select a single entry.

Calling new() without parameters returns an empty Act::Object.

If no entry is found, return C<undef>.

=cut

sub new {
    my ( $class, %args ) = @_;

    return bless {}, $class unless %args;

    # FIXME - check if the keys of %args are in fields
    # croak if some aren't?

    my $items = $class->get_items( %args );
    return undef if @$items != 1;

    $items->[0];
}

=item create( %args )

Create a new entry in the database with the corresponding parameters
set and return a Act::Object corresponding to the newly created object.

FIXME: if %args correspond to several entries in the database,
create() will return undef.

=cut

sub create {
    my ($class, %args ) = @_;
    $class = ref $class  || $class;

    my $item = $class->new( %args );
    return undef if $item;

    my $table;
    { no strict 'refs'; $table = ${"${class}::table"}; }
    my $SQL = sprintf "INSERT INTO $table (%s) VALUES (%s);",
                      join(",", keys %args), join(",", ( "?" ) x keys %args);
    my $sth = $Request{dbh}->prepare_cached( $SQL );
    $sth->execute( values %args );
    $sth->finish();
    $Request{dbh}->commit;

    return $class->new( %args );
}

=item accessors

All the accessors give read access to the data held in the entry.
The accessors are automatically named and created after the database
columns.

=cut

sub init {
    my $class = shift;
    $class = (ref $class) || $class;

    return unless %Request;

    no strict 'refs';
    my $table = ${"${class}::table"};
    my $sth   = $Request{dbh}->prepare("SELECT * from $table limit 0;");
    $sth->execute;
    my $fields = ${"${class}::fields"} = $sth->{NAME};
    $sth->finish;

    # create all the accessors at once
    for my $a (@$fields) { print $a,$/;*{"${class}::$a"} = sub { $_[0]{$a} } }
}

=back

=head2 Class methods

Act::Object also defines the following class methods:

=over 4

=item get_items( %req )

Return a reference to an array of Act::Object objects matching the request
parameters.

Acceptable parameters depend on the actual Act::Object subclass
(See L<SUBCLASSES>).

The C<limit> and C<offset> options can be given to limit
the number of results. All other parameters are ignored.

=cut

sub get_items {
    my ( $class, %args ) = @_;
    $class = ref $class  || $class;

    # search field to SQL mapping
    my %req;
    { no strict 'refs'; %req = %{"${class}::sql_mapping"}; }

    # SQL options
    my %opt = (
        offset   => '',
        limit    => '',
    );
    
    # clean up the arguments and options
    exists $args{$_} and $opt{$_} = delete $args{$_} for keys %opt;
    $opt{$_} =~ s/\D+//g for qw( offset limit );
    for( keys %args ) {
        # ignore search attributes we do not know
        delete $args{$_} unless exists $req{$_};
        # remove empty search attributes
        delete $args{$_} unless $args{$_};
    }

    # SQL options for the derived class
    { no strict 'refs'; %opt = ( %opt, %{"{$class}::sql_opts"} ); }

    # build the request string
    my $SQL;
    { no strict 'refs'; $SQL = ${"${class}::sql_stub"}; }
    $SQL .= join " AND ", "TRUE", @req{keys %args};
    $SQL .= join " ", "", map { $opt{$_} ne '' ? ( uc, $opt{$_} ) : () }
                          keys %opt;

    # run the request
    my $sth = $Request{dbh}->prepare_cached( $SQL );
    $sth->execute( values %args );

    my ($items, $item) = [ ];
    push @$items, bless $item, $class while $item = $sth->fetchrow_hashref();

    $sth->finish();

    return $items;
}

=back

These classes can also be called on an object instance.

=head1 SUBCLASSES

Creating a subclass of Act::Object should be quite easy:

    package Act::Foo;
    use Act::Object;
    use base qw( Act::Object );

    # information used by new()
    our $new_args = qr/^(?:foo_id|user_id)$/;

    # information used by create()
    our $table = "foos";     # the table holding object data

    # information used by get_items()
    our $sql_stub = "SELECT f.* FROM foos f WHERE ";
    our %sql_opts = ();      # SQL options for get_items()
    out %sql_mapping = (
          bar => "(
          map { ( $_, "(f.$_=?)" ) } qw( foo_id conf_id ),
    );

    # Your class now inherits new(), create(), get_items()
    # and the AUTOLOADED accessors (for the column names)

    # Alias the search method
    *get_foos = \&Act::Object::get_items;

    # Create the accessors and helper methods
    Act::Foo->init();

See Act::User for a slightly more complicated setup.

=cut

1;
