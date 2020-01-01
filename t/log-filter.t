use Test::Spec;
use Test::Differences;
use File::Slurp;
use POSIX qw(strftime);
require "log-filter";

describe "log-filter" => sub {
	it "splits log lines" => sub {
		my $sample = "
word_a word_b
word_c word_d
-------------
word_e word_f
    ";
		my $result = [ split_lines($sample) ];
		my $expected = ["
word_a word_b
word_c word_d
", "
word_e word_f
    "
		];

		eq_or_diff($result, $expected);
	};

	it "break down logs and split words" => sub {
		my $sample = "
word_a word_b
word_c word_d
    ";
		my $result = [ split_words($sample) ];
		my $expected = ["word_a", "word_b", "word_c", "word_d"];

		eq_or_diff($result, $expected);
	};

	it "removes numbers and special characters" => sub {
		my $sample = "
    [Tue Dec 31 17:37:55 2019] [warn1] [NOT-EVENT-LOGGED] 14263 1 c61b74de37b70003 /extranet/reservations/retrieve_list
    [Request: POST /fresa/extranet/reservations/retrieve_list?perpage=50&page=1&hotel_id=2377246&lang=xu&date_type=arrival&date_from=2019-11-12&date_to=2019-11-13&ses=f33ee24c9215f389d365af1e1d2ddc26&token=empty-token&user_triggered_search=0 HTTP/1.1]
    intercom find_thread() failed: Error from Intercom 500: Internal Server Error

    reservation_ids: 2333685970 3796970216 at /usr/local/git_tree/main/lib/Foo/Intercom/PerlAPI/Thread.pm line 370.
    Deployment: extranet-20191217-141532_fake (0ba5bcce071a47424d73d88d28fa1050b769ba44)
	  Foo::Intercom::PerlAPI::Thread::__ANON__(STR) called at /usr/lib/pakket/5.28.1/libraries/active/lib/perl5/x86_64-linux/AnyEvent/XSPromises/Loader.pm line 54
    ";

		my $result = [ split_words($sample) ];
		my $expected = ['Tue','Dec','warn','NOT-EVENT-LOGGED','cbdeb','extranet','reservations','retrieve_list','Request','POST','fresa','extranet','reservations','retrieve_listperpagepagehotel_idlangxudate_typearrivaldate_from--date_to--sesfeecfdafedddctokenempty-tokenuser_triggered_search','HTTP','intercom','find_thread','failed','Error','from','Intercom','Internal','Server','Error','reservation_ids','at','usr','local','git_tree','main','lib','Foo','Intercom','PerlAPI','Threadpm','line','Deployment','extranet--_fake','babcceadddfabba','Foo','Intercom','PerlAPI','Thread','__ANON__STR','called','at','usr','lib','pakket','libraries','active','lib','perl','x_-linux','AnyEvent','XSPromises','Loaderpm','line'];

		eq_or_diff($result, $expected);
	};

	it "filters logs with specific words" => sub {
		my $result = `echo "foo bar\n-------\nbaz\nqux\n-------\nalpha beta" | ./log-filter --words foo,baz`;
		eq_or_diff($result, "\nalpha beta\n");
	};

	xit "filters logs with specific words generated over time" => sub {
		my $result = `perl producer.pl | ./log-filter --words hey,ho`;
		eq_or_diff($result, "let's go\n");
	};

	it "saves processed logs" => sub {
		`rm ~/.log-filter-history`;
		`echo "51 foo bar" | ./log-filter`;
		`echo "52 foo bar" | ./log-filter`;
		my $result = read_file($ENV{"HOME"} . '/.log-filter-history');
		my $today = strftime "%Y-%m-%d", localtime;

		eq_or_diff($result, "$today:foo,bar\n$today:foo,bar\n");
	};

	it "parses history counting words" => sub {
		my $history = "2020-01-01:foo,bar,baz
2020-01-01:foo,bar
2020-01-02:foo,baz
2020-01-02:foo,baz,bar
";
		write_file($ENV{"HOME"} . '/.log-filter-history', $history);
		my $result = parse_history();

		eq_or_diff($result, {
			'2020-01-01' => {
				'foo' => 2,
				'bar' => 2,
				'baz' => 1,
			},
			'2020-01-02' => {
				'foo' => 2,
				'bar' => 1,
				'baz' => 2,
			},
		});
	};

	it "calculates probability of a word to be in each date given history" => sub {
		my $history = {
			'2020-01-01' => {
				'foo' => 3,
				'bar' => 2,
				'baz' => 1,
			},
			'2020-01-02' => {
				'foo' => 1,
				'bar' => 1,
				'baz' => 2,
			},
		};
		my $result = posteriors("foo", $history);
		my $expected = {
			# P(2020-01-01|foo) = [ P(foo|2020-01-01) * P(2020-01-01) ] / P(foo)
			# P(2020-01-01|foo) = [ 0.5 * 0.6 ] / 0.4
			# P(2020-01-01|foo) = 0.75
			'2020-01-01' => 0.75,
			'2020-01-02' => 0.25,
		};
		eq_or_diff($result, $expected);
	};
};

runtests();