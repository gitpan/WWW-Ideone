package WWW::Ideone;
use warnings;
use strict;
use Template;
use LWP::UserAgent;
use Carp;
use IO::Uncompress::Gunzip qw/gunzip $GunzipError/;

our $VERSION = 0.04;

# The version of soap which we must use to be understood by ideone.com.

our $soap_version = 'xmlns:env="http://www.w3.org/2003/05/soap-envelope"';

# The URL we send our input to

our $ideone_api_url = 'http://ideone.com/api/1/service';

# The template from which we create the XML request to ideone.com.

my $ideone_request_tmpl = <<'EOF';
<?xml version="1.0" encoding="UTF-8"?>
<env:Envelope [% ideone.soap_version %]>
  <env:Body>
    <m:[% ideone.command %]>
[%- FOR field IN fields.keys.sort %]
      <[% field %]>[% fields.$field | xml %]</[% field %]>
[%- END %]
    </m:[% ideone.command %]>
  </env:Body>
</env:Envelope>
EOF

# The fields which we can send to ideone.com

my %fields = (
    user
        => 
        {
            type => 'string',
        },
    pass
        => 
        {
            type => 'string',
        },
    sourceCode
        => 
        {
            type => 'string',
        },
    language
        =>
        {
            type => 'number',
        },
    input
        =>
        {
            type => 'string',
            default => '',
        },
    run
        =>
        {
            type => 'boolean',
            default => 'true',
        },
    private
        =>
        {
            type => 'boolean',
            default => 'false',
        },
    # "link" is a Perl keyword so this needs quotes
    'link'
        =>
        {
            type => 'string',
        },
    withSource
        =>
        {
            type => 'boolean',
            default => 'false',
        },
    withInput
        =>
        {
            type => 'boolean',
            default => 'false',
        },
    withOutput
        =>
        {
            type => 'boolean',
            default => 'false',
        },
);

# The commands which we know about.

my %commands = (
    'createSubmission' => {
        params => [
            qw/
                  sourceCode
                  language
                  input
                  run
                  private
              /,
        ],
    },
    'get_submissionStatus' => {
        params => [
            qw/
                  link
              /,
        ],
    },
    'get_submissionDetails' => {
        params => [
            qw/
                  withSource
                  withInput
                  withOutput
              /,
        ],
    },
    'getLanguages' => {
        params => [],
    },
    'testFunction' => {
        params => [],
    },
);

# All of these need a user and pass field.

for my $i (values %commands) {
    push @{$i->{params}}, qw/user pass/;
}

sub new
{
    return bless {};
}

sub run_tt
{
    my ($unused, $input_template, $tt_vars_ref) = @_;
    my $tt = Template->new (
        ABSOLUTE => 1,
        INCLUDE_PATH => ["$FindBin::Bin/tmpl"],
    );
    $tt_vars_ref->{ideone}{soap_version} = $soap_version;
    my $tt_out;

    $tt->process ($input_template, $tt_vars_ref, \$tt_out);
    return $tt_out;
}

# Validate the field C<$field>

sub validate
{
    my ($input_fields) = @_;
    for my $field (keys %$input_fields) {
        if (! $fields{$field}) {
            croak "Unknown field '$field'";
        }
    }
}

# 

sub check_inputs
{
    my ($command, $input_fields) = @_;
    my $params = $commands{$command}{params};
    my %expect;
    for my $field (@$params) {
        if (! defined $input_fields->{$field}) {
            my $default = $fields{$field}{default};
            if (defined $default) {
                $input_fields->{$field} = $default;
            }
            else {
                croak "Required input '$field' for '$command' is undefined";
            }
        }
        $expect{$field} = 1;
    }
    for my $field (keys %$input_fields) {
        if (! defined $expect{$field}) {
            carp "Method '$command' does not require a '$field' input";
            delete $input_fields->{$field};
        }
    }
}

sub make_tt
{
    my ($unused, %input) = @_;
    my $tt = Template->new ();
    my $input_fields = $input{fields};
    if (! defined $input_fields) {
        $input_fields = {};
    }
    $input_fields->{user} = $unused->{ideone}->{user};
    $input_fields->{pass} = $unused->{ideone}->{pass};
    validate ($input_fields);
    my $command = $input{command};
    if (! defined $command) {

    }
    check_inputs ($command, $input_fields);
    if (! $commands{$command}) {
        croak "Unknown command '$command'";
    }
    my %tt_vars;
    $tt_vars{fields} = $input_fields;
    undef $input_fields;
    $tt_vars{ideone}{command} = $command;
    undef $command;
    $tt_vars{ideone}{soap_version} = $soap_version;
    my $tt_out;

    $tt->process (\$ideone_request_tmpl, \%tt_vars, \$tt_out);
    return $tt_out;
}


sub send_request
{
    my ($unused, $content) = @_;
    my $ua = LWP::UserAgent->new (agent => __PACKAGE__);
    my $response = $ua->post (
        $ideone_api_url,
        'Content-Type' => 'application/soap+xml; charset=utf-8',
        'Content-Length' => length $content,
        'Accept-Encoding' => 'gzip',
        content => $content,
    );
    if ($response->is_success ()) {
        my $content = $response->content ();
        # gunzip if necessary
        if ($response->header ('Content-Encoding') eq 'gzip') {
            my $unzipped_content;
            gunzip \$content, \$unzipped_content
                or die "gunzip failed: $GunzipError.\n";
            $content = $unzipped_content;
        }
        return $content;
    }
    else {
        croak "Request failed with the following message:\n" .
            $response->as_string ();
    }
}

sub send
{
    my $object = $_[0];
    my $message = make_tt (@_);
    my $reply = $object->send_request ($message);
    return $reply;
}

sub get_languages
{
    my ($object) = @_;
    my $lang_xml = $object->send (command => 'getLanguages');
    my %languages;
    while ($lang_xml =~ m!<key[^>]+>(\d+)</key><value[^>]+>([^<]+)</value>!g) {
        $languages{$1} = $2;
    }
    return %languages;
}

sub user_pass
{
    my ($object, $user, $pass) = @_;
    $object->{ideone}->{user} = $user;
    $object->{ideone}->{pass} = $pass;
}

sub parse_xml
{
    my ($unused, $xml) = @_;

    my @return = xml_contents ($xml, 'return');
 
    my %hash;
    for (@return) {
        my @items = xml_contents ($_, 'item');
        for my $item (@items) {
            my @key = xml_contents ($item, 'key');
            my @value = xml_contents ($item, 'value');
            $hash{$key[0]} = $value[0];
        }
    }
    return %hash;
}

sub xml_contents
{
    my ($xml, $tag) = @_;
    my @contents;

    while ($xml =~ m!<$tag[^>]*>(.*?)</$tag>!smg) {
        push @contents, $1;
    }
    return @contents;
}


1;

