package MT::Plugin::SpamSubmission;
# $Id$
use strict;
use base qw(MT::Plugin);

use MT::Comment;
use MT::TBPing;

our $VERSION = "0.90";

my $plugin = MT::Plugin::SpamSubmission->new({
    name => "SpamSubmission",
    version => $VERSION,
    description => "Submit URLs and IPs found in your junked feedbacks (Comments/Trackbacks) via Bulkfeeds SPAM Submission API",
    author_name => 'Tatsuhiko Miyagawa',
    author_link => 'http://blog.bulknews.net/mt/',
    config_template => 'spam_submission.tmpl',
    settings => MT::PluginSettings->new([
        ['auth_type' => { Default => 'apikey' }],
        ['apikey'],
        ['typekey_username'],
        ['typekey_password'],
    ]),
});

MT->add_plugin($plugin);

sub instance { $plugin }

sub uniq {
    my @list = @_;
    my %uniq;
    $uniq{$_}++ for @list;
    keys %uniq;
}

for my $class (qw(MT::Comment MT::TBPing)) {
    no strict 'refs';
    local $SIG{__WARN__} = sub { };
    my $old = $class->can('junk');
    *{$class . "::junk"} = sub {
        my $obj = shift;
        my @urls = uniq(find_uris($obj->all_text));
        submit_spams(\@urls);
        $obj->$old(@_);
    };
}

sub find_uris {
    my $text = shift;
    return $text =~ /https?:\/\/[-_.!~*'()a-zA-Z0-9;\/?:\@&=+\$,%#]+/g; #']/;
}

sub submit_spams {
    my $urls_ref = shift;

    ## prepare API key
    my %apikeys = prepare_apikeys();
    %apikeys or do {
        MT::log("No API key configuration for SpamSubmission");
        return;
    };

    MT::log("Submitting " . join(" ", @$urls_ref) . " as Blacklist");
    my $ua = MT->new_ua;
    $ua->agent($plugin->name . "/" . $plugin->version);
    $ua->timeout(5);

    my $res = $ua->post("http://bulkfeeds.net/app/submit_spam", {
        url => join("\n", @$urls_ref),
        %apikeys,
    });
}

sub prepare_apikeys {
    my $config = MT::Plugin::SpamSubmission->instance->get_config_hash;
    if ($config->{auth_type} eq 'apikey') {
        return $config->{apikey} ? (apikey => $config->{apikey}) : ();
    } else {
        # request TypeKey auth
        my($user, $pass) = @{$config}{qw(typekey_username typekey_password)};
        return unless $user && $pass;

        require HTTP::Request::Common;
        my $req = HTTP::Request::Common::POST(
            "https://www.typekey.com/t/typekey/login", [
                __mode => 'save_login',
                _return => 'http://bulkfeeds.net/app/submit_spam.xml?__tk=1',
                t => 'pIP85xqmwm2l37HOgBrA',
                v => '1.1',
                need_email => 1,
                username => $user,
                password => $pass,
            ],
        );

        my $ua = MT->new_ua;
        $ua->agent($plugin->name . "/" . $plugin->version);
        my $res = $ua->simple_request($req);
        if ($res->is_redirect and my $loc = $res->header('Location')) {
            my $uri = URI->new($loc);
            return $uri->query_form;
        }
    }

    return;
}

1;

