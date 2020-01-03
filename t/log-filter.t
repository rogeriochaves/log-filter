use Test::Spec;
use Test::Differences;
use File::Slurp;
use POSIX qw(strftime);
require "log-filter";

describe "log-filter" => sub {
	describe "basics" => sub {
		it "splits log lines" => sub {
			my $sample = "
	word_a word_b
	word_c word_d
	-------------
	word_e word_f
	==> /file <==
	word_g
			";
			my $result = [ split_lines($sample) ];
			my $expected = ["
	word_a word_b
	word_c word_d
	", "
	word_e word_f
	",
				"
	word_g
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
			my $result = `echo "foo bar\n-------\nbaz\nqux\n-------\nalpha beta" | ./log-filter --block foo,baz`;
			eq_or_diff($result, "\nalpha beta\n");
		};

		xit "filters logs with specific words generated over time" => sub {
			my $result = `perl producer.pl | ./log-filter --block hey,ho`;
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

			eq_or_diff(
				$result,
				{
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
				}
			);
		};
	};

	describe "bayesian calculations" => sub {
		my $history = {
			'2020-01-01' => {
				'foo' => 3,
				'bar' => 2,
				'baz' => 1,
			},
			'2020-01-02' => {
				'foo' => 1,
				'bar' => 1,
				'qux' => 2,
			},
		};

		it "calculates probability of a word to be in each date given history" => sub {
			my $result = word_posteriors('foo', $history, calculate_totals(['foo'], $history));
			my $expected = {

				# P(2020-01-01|foo) = [ P(foo|2020-01-01) * P(2020-01-01) ] / P(foo)
				# P(2020-01-01|foo) = [ 0.5 * 0.6 ] / 0.4
				# P(2020-01-01|foo) = 0.75
				'2020-01-01' => 0.75,
				'2020-01-02' => 0.25,
			};
			eq_or_diff($result, $expected);
		};

		it "calculates probability of unseen word" => sub {
			my $result = word_posteriors('xpto', $history, calculate_totals(['xpto'], $history));
			my $expected = {
				'2020-01-01' => 0.1,
				'2020-01-02' => 0.1,
			};
			eq_or_diff($result, $expected);
		};

		it "calculates probability of words not available in all dates, with maximum probability to avoid multiplication by 0 errors" => sub {
			my $result = word_posteriors('qux', $history, calculate_totals(['qux'], $history));
			my $expected = {
				'2020-01-01' => 0.1,
				'2020-01-02' => 0.99,
			};
			eq_or_diff($result, $expected);
		};

		it "calculates probability of all words" => sub {
			my $result = posteriors(['foo', 'bar'], $history);
			my $expected = {
				'2020-01-01' => {
					'foo' => 0.75,
					'bar' => 2 / 3,
				},
				'2020-01-02' => {
					'foo' => 0.25,
					'bar' => 1 / 3,
				},
			};
			eq_or_diff($result, $expected);
		};

		it "selects n most relevant words and calculate their combined probabilities according to Graham" => sub {
			my $posteriors = {
				'2020-01-01' => {
					'foo' => 0.95,
					'bar' => 0.85,
					'baz' => 0.06,
				},
				'2020-01-02' => {
					'foo' => 0.65,
					'bar' => 0.85,
					'baz' => 0.05,
				},
			};
			my $n = 2;
			my $result = combined_probability($posteriors, $n);
			my $expected = {

				# (P(foo) * P(baz)) / [ (P(foo) * P(baz)) + ((1 - P(foo)) * (1 - P(baz))) ]
				# (0.95 * 0.06) / [ (0.95 * 0.06) + (0.05 * 0.94) ]
				# 0.548076923
				'2020-01-01' => 0.548076923076923,
				'2020-01-02' => 0.22972972972973,
			};
			eq_or_diff($result, $expected);
		};
	};

	describe "integration" => sub {
		before each => sub {
			my $today = strftime "%Y-%m-%d", localtime;
			my $yesterday = strftime "%Y-%m-%d", localtime(time() - 24*60*60);
			my $two_days_ago = strftime "%Y-%m-%d", localtime(time() - 24*60*60*2);
			my $three_days_ago = strftime "%Y-%m-%d", localtime(time() - 24*60*60*3);
			my $four_days_ago = strftime "%Y-%m-%d", localtime(time() - 24*60*60*4);

			my $history = "$four_days_ago:wut
$three_days_ago:foo,bar,baz
$three_days_ago:foo,meh
$two_days_ago:lalalala
$yesterday:foo,wut,lol,lol,lol
$today:wut,lol
";
			write_file($ENV{"HOME"} . '/.log-filter-history', $history);
		};

		it "filters out logs which have probabily appeared in the past days" => sub {
			my $result = `echo "foo\n-------\nnew log" | ./log-filter`;
			eq_or_diff($result, "\nnew log\n");
		};

		it "keeps logs which have maybe appeared on the past days but also today" => sub {
			my $result = `echo "foo\n-------\nmeh" | ./log-filter`;
			eq_or_diff($result, "\nmeh\n");
		};

		it "keeps logs which which appeared mostly yesterday but is still quite fresh to show it today as well" => sub {
			my $result = `echo "foo\n-------\nlol" | ./log-filter`;
			eq_or_diff($result, "\nlol\n");
		};
	};

	it "clears older logs" => sub {
		my $today = strftime "%Y-%m-%d", localtime;
		my $long_ago = strftime "%Y-%m-%d", localtime(time() - 24*60*60*15);
		my $history = "$long_ago:wut
$today:bar
";
		write_file($ENV{"HOME"} . '/.log-filter-history', $history);
		`echo "foo" | ./log-filter`;

		my $result = read_file($ENV{"HOME"} . '/.log-filter-history');

		eq_or_diff($result, "$today:bar\n$today:foo\n");
	};
};

runtests();