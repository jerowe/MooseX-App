# ============================================================================
package MooseX::App::ParsedArgv;
# ============================================================================

use 5.010;
use utf8;

use Moose;

use Encode qw(decode);

my $SINGLETON;

has 'argv' => (
    is              => 'rw',
    isa             => 'ArrayRef[Str]',
    lazy_build      => 1,
);

has 'options' => (
    is              => 'rw',
    isa             => 'ArrayRef[MooseX::App::ParsedArgv::Option]',
    lazy_build      => 1,
);

has 'extra' => (
    is              => 'rw',
    isa             => 'ArrayRef[Str]',
    lazy_build      => 1,
);


sub BUILD {
    my ($self) = @_;
    $SINGLETON = $self;
}

sub instance {
    my ($class) = @_;
    unless (defined $SINGLETON) {
        return $class->new();
    }
    return $SINGLETON;
}

sub shift_argv {
    my ($self) = @_;
    
    my $argv = $self->_argv;
    my $first_argv = shift @{$argv};
    
    my $meta = $self->meta;
    $meta->get_attribute('options')->clear_value($self);
    $meta->get_attribute('extra')->clear_value($self);
    
    return $first_argv;
}

sub _build_options {
    my ($self) = @_;
    $self->_parse();
    my ($options,$extra) = $self->options;
    return $options;
}

sub _build_extra {
    my ($self) = @_;
    $self->_parse();
    my ($options,$extra) = $self->extra;
    return $extra;
}

sub _parse {
    my ($self) = @_;
    
    my %options;
    my $lastkey;
    my $stopprocessing;
    my @extra;
    
    foreach my $element (@{$self->argv}) {
        if ($stopprocessing) {
            push(@extra,$element);
        } else {
            given ($element) {
                # Flags
                when (m/^-([^-][[:alnum:]]*)$/) {
                    undef $lastkey;
                    foreach my $flag (split(//,$1)) {
                        $options{$flag} ||= MooseX::App::ParsedArgv::Option->new( key => $flag );
                        $lastkey = $options{$flag};  
                    }
                }
                # Key-value combined
                when (m/^--([^-=][^=]*)=(.+)$/) {
                    undef $lastkey;
                    my ($key,$value) = ($1,$2);
                    $options{$key} ||= MooseX::App::ParsedArgv::Option->new( key => $key );
                    $options{$key}->add_value($value);
                }
                # Key
                when (m/^--([^-].*)/) {
                    my $key = $1;
                    $options{$key} ||= MooseX::App::ParsedArgv::Option->new( key => $key );
                    $lastkey = $options{$key};
                }
                # Extra values
                when ('--') {
                    undef $lastkey;
                    $stopprocessing = 1;
                }
                # Value
                default {
                    if (defined $lastkey) {
                        $lastkey->add_value($element);
                        undef $lastkey;
                    } else {
                        push(@extra,$element);
                    }
                }
            } 
        }
    }
    
    # Sort by length    
    my @options = sort { length($b->key) <=> length($a->key) } values %options;
    
    # Fill empty slots
    foreach my $option (@options) {
        unless ($option->has_values()) {
            $option->add_value(1);
        }   
    }
    
    my $meta = $self->meta;
    $meta->get_attribute('options')->set_raw_value($self,\@options);
    $meta->get_attribute('extra')->set_raw_value($self,\@extra);
    
    return (\%options,\@extra);
}

sub options_available {
    my ($self) = @_;
    
    my @options;
    foreach my $option (@{$self->options}) {
        next
            if $option->is_consumed;
        push(@options,$option);
    }  
    return @options; 
}

sub _build_argv {
    my @argv = eval {
        require I18N::Langinfo;
        I18N::Langinfo->import(qw(langinfo CODESET));
        my $codeset = langinfo(CODESET());
        # TODO Not sure if this is the right place?
        binmode(STDOUT, ":encoding(UTF-8)")
            if $codeset =~ m/^UTF-?8$/i;
        return map { decode($codeset,$_) } @ARGV;
    };
    
    # TODO handle errors
    return \@argv;
}


{
    package MooseX::App::ParsedArgv::Option;
    
    use Moose;
    
    has 'key' => (
        is              => 'ro',
        isa             => 'Str',
        required        => 1,
    );
    
    has 'value' => (
        is              => 'rw',
        isa             => 'ArrayRef[Str]',
        traits          => ['Array'],
        default         => sub { [] },
        handles => {
            add_value       => 'push',
            has_values      => 'count',
        }
    );
    
    has 'consumed' => (
        is              => 'rw',
        isa             => 'Class::MOP::Attribute',
        predicate       => 'is_consumed',
    );
    
    sub consume {
        my ($self,$attribute) = @_;
        Moose->throw_error('Option '.$self->key.' is already consumed')
            if $self->consumed;
        $self->consumed($attribute);  
        
        return $self; 
    }
    
    __PACKAGE__->meta->make_immutable();
}

__PACKAGE__->meta->make_immutable;
1;