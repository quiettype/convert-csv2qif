#!/usr/bin/perl

# convert-cvsqif.pl
# Tool to clean up qif files from banks, for import into MS Money
#
# Remember to add complex enties first, to ensure maximal match
#
# ref. http://en.wikipedia.org/wiki/QIF#Data_Format

# GPL 2.0 - initial version from quiettype.

# Changelog:
# 1.0 - initial draft for St George Bank
# 2.0 - included Commbank weirdess
# 2.1 - added Members Equity multi transaction entries (email sent to ME)
# 2.1a - output filename now uses source name
# 2.2 - added Centrelink (child benfit)
# 2.3 - added to git version control 
# 2.4 - code cleanup - remove whitespace..
use constant version => "2.4";

use File::stat;

sub Error {
	my ($str) = @_;

	print "ERROR: $str\n";
	die;
}

my ( $mydir, $out_path, $in_path, $out, $buf );

if ( @ARGV == 0 ) {
	printf("convert-csvqif.pl - CSV converter for MS Money import\nVersion: %s\n",version);
	exit;
}

if ( $#ARGV > 1 ) {
	Error("Too many args\n");
}

$out_path = $in_path = $ARGV[0];
$out_path =~ s/.csv$/_out.qif/;

open( $in_path, "<:raw", $in_path )    # :crlf"
  || Error("can't open $in_path :$!");

$sb = stat($in_path);

# read file into buffer
$numread = read( $in_path, $buf, $sb->size );
if ( $numread != $sb->size ) {
	Error( "read failed: $numread - " . $sb->size . " $!" );
}

# close input file
close $in_path;

# convert to UPPER
$buf =~ tr/a-z/A-Z/;
%mon2num = qw(
  JAN 01  FEB 02  MAR 03  APR 04 MAY 05 JUN 06
  JUL 07  AUG 08  SEP 09  OCT 10 NOV 11 DEC 12
);

SWITCH:
while ( length $buf ) {
	my ( $date, $amt, $type, $who, $cmt, $total, $tmp_total );

	#01-Jan-01,-218.05,,,EFTPOS DEBIT PURCH CASH-FLEXIPAY,,3865.84,
	if ( $buf =~
		s/([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)\n// )
	{
		$date  = $1;
		$amt   = $2;
		$type  = $5;
		$who   = $6;
		$cmt   = $7;
		$total = $7;

		# Normalise date
		$date =~ tr|-|/|;
		if ( $date =~ /([0-9]{2})\/([A-Z]{3})\/([0-9]{2})/ ) {
			$date = $1 . '/' . $mon2num{$2} . '/' . $3;
		}

		# 1. Salary
		if ( $type =~ /^SALARY SALARY$/ ) {
			print "$date: 1. salary - '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nM1. SALARY $who ($total)\n^\n";
			next;
		}

		# 2. ATM DEBIT
		if ( $type =~ /^ATM DEBIT/ ) {
			print "$date: 2. ATM debt- '$who' $amt\n";
			$out .= "D$date\nPcash\nT$amt\nM2.ATM DEBIT $who ($total)\n^\n";
			next;
		}

		# 3. DEPOSIT CASH
		if ( $type =~ /^DEPOSIT CASH$/ ) {
			print "$date: 3. DEPOSIT CASH- '$who' $amt\n";
			$who = "cash";
			$out .= "D$date\nP$who\nT$amt\nM3.DEPOSIT CASH $who ($total)\n^\n";
			next;
		}

		# 4.1. EFTPOS DEBIT PURCH CASH, EFTPOS
		# 01/01/01,-63.87,,,EFTPOS DEBIT PURCH CASH-FLEXIPAY,
		#     EFTPOS 21/07 15:55  L/LAND  WEST LAKES  CASH OUT    $40.00,982.08,
		if (   $type =~ /^EFTPOS DEBIT PURCH CASH$/
			&& $who =~ /EFTPOS [0-9]*\/[0-9]* [0-9]*\:[0-9]*\s*([^,]*?)\s*CASH OUT * \$([0-9.]*)$/
		  )
		{

			# EFTPOS 01/01 15:55  L/LAND  WEST LAKES  CASH OUT    $40.00
			$company = $1;
			$cash    = $2;
			$amt += $cash;
			$tmp_total = $total - $cash;
			print "$date: 4.1. EFTPOS DEBIT PURCH (+CASH follow)- '$company' $amt, $tmp_total \n";
			$out .= "D$date\nP$company\nT$amt\nM4.1.  $company eftpos(+cash) ($tmp_total)\n^\n";

			print "$date: 4.1. EFTPOS DEBIT PURCH CASH - '$who' -$cash ($total)\n";
			$out .= "D$date\nPcash\nT-$cash\nM4.1. (eftpos+)cash $who ($total)\n^\n";
			next;
		}

		# 4.2 EFTPOS DEBIT PURCH CASH, EFTPOS
		# 01/01/01,-218.05,,,EFTPOS DEBIT PURCH CASH-FLEXIPAY,,3865.84,
		
        # 4.2. EFTPOS 01/01 17:50  COLES  PORT ADELAIDECASH OUT    $50.00 (4944.99)
		if ( $type =~ /^EFTPOS DEBIT PURCH CASH-FLEXIPAY$/ 			
		&& $who =~ /EFTPOS [0-9]*\/[0-9]* [0-9]*\:[0-9]*\s*([^,]*?)\s*CASH OUT * \$([0-9.]*)$/
		) {
			$company = $1;
			$cash    = $2;
			$amt += $cash;
			$tmp_total = $total - $cash;

			print "$date: 4.2. EFTPOS DEBIT PURCH CASH FLEXIPAY- '$who' -$cash ($total)\n";
			$out .= "D$date\nPcash\nT-$cash\nM4.1. (eftpos+)cash $who ($total)\n^\n";
			print "$date: 4.2. EFTPOS DEBIT PURCH CASH FLEXIPAY- '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nM4.2. $who ($total)\n^\n";
			next;
		}
		
        # 4.2a EFTPOS 01/01 17:50  COLES  PORT ADELAIDECASH OUT    $50.00 (4944.99)
		if ( $type =~ /^EFTPOS DEBIT PURCH CASH-FLEXIPAY FIXME$/ ) {
			print "$date: 4.2a. EFTPOS DEBIT PURCH CASH - '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nM4.2a. $who ($total)\n^\n";
			next;
		}

		# 4.3 EFTPOS DEBIT PURCHASE-FLEXIPAY
		# 01/01/01,-50.8,,,EFTPOS DEBIT PURCHASE-FLEXIPAY,EFTPOS 01/01 10:35  SILVERS AUTO CTR,4083.89,
		if (   $type =~ /^EFTPOS DEBIT PURCHASE-FLEXIPAY$/
			&& $who =~ /EFTPOS [0-9]*\/[0-9]* [0-9]*\:[0-9]*\s*([^,]*?)$/ )
		{
			$company = $1;
			print "$date: 4.3. EFTPOS DEBIT PURCHASE-FLEXIPAY - '$company' '$who' $amt\n";
			$out .= "D$date\nP$company\nT$amt\nM4.3. EFTPOS DEBIT PURCHASE-FLEXIPAY $who ($total)\n^\n";
			next;
		}

		# 4.4 EFTPOS DEBIT PURCHASE-FLEXIPAY
		if ( $type =~ /^EFTPOS DEBIT PURCHASE-FLEXIPAY$/ ) {
			print "$date: 4.4. EFTPOS DEBIT PURCHASE-FLEXIPAY - '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nM4.4. EFTPOS DEBIT PURCHASE-FLEXIPAY $who ($total)\n^\n";
			next;
		}

		# 4.5 01/01/01,-26.98,EFTPOS DEBIT,EFTPOS 01/01 13:55 COLES PORT ADELAIDE SA AU,-1.42
		if (   $type =~ /^EFTPOS DEBIT$/
			&& $who =~ /EFTPOS [0-9]*\/[0-9]* [0-9]*\:[0-9]*\s*([^,]*?)$/ )
		{
			$company = $1;
			print "$date: 4.5. EFTPOS DEBIT PURCHASE-FLEXIPAY - '$company' '$who' $amt\n";
			$out .= "D$date\nP$company\nT$amt\nM4.5. EFTPOS DEBIT PURCHASE-FLEXIPAY $who ($total)\n^\n";
			next;
		}

		# 5. FAMILY ALLOWANCE
		if (   $type =~ /^FAMILY ALLOWANCE/
			&& $who =~ /T[A-Z0-9]*\s*([^,]*?)$/ )
		{
			$company = $1;
			print "$date: 5. FAMILY ALLOWANCE- '$who' $amt\n";
			$out .= "D$date\nP$company\nT$amt\nM5. $who ($total)\n^\n";
			next;
		}

		# 6a. FEES DIR CHG
		if ( $type =~ /^FEES DIR CHG/ ) {
			print "$date: 6a. FEES DIR CHG- '$who' $amt\n";
			$out .= "D$date\nPATM\nT$amt\nM6a. $who ($total)\n^\n";
			next;
		}

		# 6b. FEES LOAN SERVICE
		if ( $type =~ /^FEES LOAN SERVICE/ ) {
			print "$date: 6b. FEES LOAN SERVICE- '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nM6b. $who ($total)\n^\n";
			next;
		}

        #6c. 01/01/01,-2.00,FEES,ANZ ATM 26TH12:06 FULHAM GARDENS SHOP DIR CHG OTH ATM,320.76
		if (   $type =~ /^FEES$/
			&& $who =~ /(.*)\sATM\s(.*)\s*([^,]*?)$/ )
		{
			$company = $2;
			print "$date: 6c. FEES - '$company' $amt\n";
			$out .= "D$date\nP$company\nT$amt\nM6c. $who ($total)\n^\n";
			next;
		}

		# 8. INTER-BANK CREDIT
		if ( $type =~ /^INTER-BANK CREDIT/ ) {
			print "$date: 8. INTER-BANK CREDIT- '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nM8. $who ($total)\n^\n";
			next;
		}

		# 9. INTEREST CHARGED
		if ( $type =~ /^INTEREST CHARGED/ ) {
			print "$date: 9. INTEREST CHARGED- '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nM9. $who ($total)\n^\n";
			next;
		}

		# a1. MISCELLANEOUS DEBIT EFTPOS
		# 01/01/01,-66.53,,,MISCELLANEOUS DEBIT EFTPOS TRANS VALUE,
		# V2016 01/01 COLES  WEST LAKES SA 74363000000,528.32,
		if (   $type =~ /^MISCELLANEOUS DEBIT EFTPOS/
			&& $who =~ /V[0-9]* [0-9]*\/[0-9]*\s*([^,]*?)$/ )
		{
			$company = $1;
			print "$date: a. MISC DEBIT EFTPOS - '$company' '$who' $amt\n";
			$out .= "D$date\nP$company\nT$amt\nMa1. $who ($total)\n^\n";
			next;
		}

		# a2. MISCELLANEOUS DEBIT,NAB INTNL TRAN FEE - (MC)
		if (   $type =~ /^MISCELLANEOUS DEBIT$/
			&& $who =~ /^NAB INTNL TRAN FEE/ )
		{
			print "$date: a2. MISC DEBIT NAB '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nMa2. $who ($total)\n^\n";
			next;
		}

		# a3. MISCELLANEOUS DEBIT WITHDRAWAL
		if ( $type =~ /^MISCELLANEOUS DEBIT WITHDRAWAL$/ ) {
			print "$date: a4. MISCELLANEOUS DEBIT WITHDRAWAL- '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nMa3. $who ($total)\n^\n";
			next;
		}

		# a4. MISCELLANEOUS DEBIT,V8322 02/01 PAYPAL * SOMEONE
		if ( $type =~ /^MISCELLANEOUS DEBIT$/ ) {
			print "$date: a4. MISCELLANEOUS DEBIT- '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nMa4. $who ($total)\n^\n";
			next;
		}

		# b. MISCELLANEOUS CREDIT REFUND-FLEXIPAY,REFUND-EFTPOS
		if ( $type =~ /^MISCELLANEOUS CREDIT REFUND-FLEXIPAY$/ ) {
			print
			  "$date: b. MISCELLANEOUS CREDIT REFUND-FLEXIPAY - '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nMb. REFUND $who ($total)\n^\n";
			next;
		}

        # b2 01/01/01,9.00,MISCELLANEOUS CREDIT,
        # REFUND-EFTPOS L/LAND WEST LAKES SA AU,128.51
		if (   $type =~ /^MISCELLANEOUS CREDIT$/
			&& $who =~ /^REFUND-EFTPOS\s(.*)/ )
		{
			$company = $1;
			print "$date: b2. MISCELLANEOUS CREDIT,REFUND '$company' $amt\n";
			$out .= "D$date\nP$company\nT$amt\nMb2. REFUND - $who ($total)\n^\n";
			next;
		}
		
        # b3 01/01/01,23.20,MISCELLANEOUS CREDIT CREDIT,
        #  V2016 01/01 TARGET  FULHAM GARDENS   SA         74363000000,8305.70
		if ( $type =~ /^MISCELLANEOUS CREDIT CREDIT/ 			
		     && $who =~ /V[0-9]* [0-9]*\/[0-9]*\s*([^,]*?)$/ ) {
			$company = $1;
			print "$date: b3. REVERSAL CREDIT '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nMb3. $who ($total)\n^\n";
			next;
		}
		
        #b4 - 01/01/01,129.00,CREDIT CARD REFUND,BUNNINGS 703000,-1250.28
		if ( $type =~ /^CREDIT CARD REFUND$/ ) {
			print
			  "$date: b. CREDIT CARD REFUND - '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nMb4. REFUND $who ($total)\n^\n";
			next;
		}

		# d. TRANSFER CREDIT
		if ( $type =~ /^TRANSFER CREDIT/ ) {
			print "$date: d. TRANSFER CREDIT '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nMd. $who ($total)\n^\n";
			next;
		}

		# e1. TRANSFER DEBIT BPAY
		# 01/01/01,-150,,,TRANSFER DEBIT INTERNET BILL PAYMNT,
		# INTERNET BPAY       MEMBERS EQUITY      5187000000000000,1602.16,
		if (   $type =~ /^TRANSFER DEBIT INTERNET BILL PAYMNT$/
			&& $who =~ /^INTERNET BPAY\s*([^,]*?)$/ )
		{
			print "$date: e1. TRANSFER DEBIT bpay '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nMe1. BPAY $who ($total)\n^\n";
			next;
		}

		# e2. TRANSFER DEBIT BPAY
		# 01/01/01,-123.75,,,TRANSFER DEBIT FLEXIPHONE BILL PAY,
		# FLEXIPHONE-BPAY     AGL South Aust P/L  729700000000000000,2499.5,
		if (   $type =~ /^TRANSFER DEBIT FLEXIPHONE BILL PAY$/
			&& $who =~ /^FLEXIPHONE-BPAY\s*([^,]*?)$/ )
		{
			$company = $1;
			print "$date: e2. Internet TRANSFER bpay '$who' $amt\n";
			$out .=
			  "D$date\nP$company\nT$amt\nMe2. Phone BPAY $who ($total)\n^\n";
			next;
		}

		# e3. TRANSFER DEBIT BPAY
		if (   $type =~ /^TRANSFER DEBIT INTERNET TRANSFER$/
			&& $who =~ /^INTERNET TRANSFER\s*([^,]*?)$/ )
		{
			$company = $1;
			print "$date: e3. Internet TRANSFER bpay '$company' '$who' $amt\n";
			$out .= "D$date\nP$company\nT$amt\nMe2. Internet transfer $who ($total)\n^\n";
			next;
		}

		# e4. 01/01/01,-50.00,TRANSFER DEBIT INTERNET BILL PAYMNT,INTERNET- BILL PAY  AGL SOUTH AUST P/L,10188.55
		if (   $type =~ /^TRANSFER DEBIT INTERNET BILL PAYMNT$/
			&& $who =~ /^INTERNET- BILL PAY\s*([^,]*?)$/ )
		{
			$company = $1;
			print "$date: e3. Internet TRANSFER bpay '$who' $amt\n";
			$out .= "D$date\nP$company\nT$amt\nMe2. Internet transfer $who ($total)\n^\n";
			next;
		}

		# e5. TRANSFER DEBIT
		if ( $type =~ /^TRANSFER DEBIT TRANSFER$/ ) {
			print "$date: e5. TRANSFER DEBIT '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nMe5. Debt transfer $who ($total)\n^\n";
			next;
		}

		# f. PURCHASE AUTHORISATION
		if ( $type =~ /^PURCHASE AUTHORISATION$/ ) {
			print "$date: f. PURCHASE AUTHORISATION '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nMf. PURCHASE AUTHORISATION $who ($total)\n^\n";
			next;
		}

		# g. CREDIT CARD PURCHASE
		if ( $type =~ /^CREDIT CARD PURCHASE$/ ) {
			print "$date: g. CREDIT CARD PURCHASE '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nMg. $who ($total)\n^\n";
			next;
		}

		# h. CREDIT CARD PAYMENT
		if ( $type =~ /^CREDIT CARD PAYMENT$/ ) {
			print "$date: h. CREDIT CARD PAYMENT '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nMh. $who ($total)\n^\n";
			next;
		}

        # i. 01/01/01,-29.00,AUTOMATIC DRAWING,96700000            VODAFONE,2524.79
		if (   $type =~ /^AUTOMATIC DRAWING$/
			&& $who =~ /^[0-9]*\s*([^,]*?)$/ ) {
			$company = $1;
			print "$date: i. AUTOMATIC DRAWING '$company' $who' $amt\n";
			$out .= "D$date\nP$company\nT$amt\nMi. AUTOMATIC DRAWING $who ($total)\n^\n";
			next;
		}

        # j. 01/01/01,-2.38,DEBIT ADJUSTMENTS,BALANCE SEGMENT TRANSFER,412.35
		if ( $type =~ /^DEBIT ADJUSTMENTS$/ ) {
			print "$date: h. DEBIT ADJUSTMENTS '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nMj. ?? DEBIT ADJUSTMENT $who ($total)\n^\n";
			next;
		}
		
        # k. 01/01/01,-2.38,CREDIT ADJUSTMENTS,BALANCE SEGMENT TRANSFER,412.35
		if ( $type =~ /^CREDIT ADJUSTMENT$/ ) {
			print "$date: h. CREDIT ADJUSTMENT '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nMk. ?? CREDIT ADJUSTMENT $who ($total)\n^\n";
			next;
		}

		# l. 01/01/01,-250.00,CREDIT CARD CASH ADVANCE,INTERNET TRANSFER LOAN PA,-3441.89
		if ( $type =~ /^CREDIT CARD CASH ADVANCE$/ ) {
			print "$date: l. CREDIT CARD CASH ADVANCE '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nMl. WOAH ---> CREDIT CARD CASH ADVANCE $who ($total)\n^\n";
			next;
		}
		
		# m. Bank notice to customers 01/01/01,0.00,,PLEASE NOTE FROM 01 JAN 2001 YOUR DEBIT INT RATE IS 17.69%,-13.86
		if ( $who =~ /^PLEASE NOTE/ ) {
			print "$date: m. Bank notice: -------=========> '$who'\n";
			next;
		}
			
		# n. 01/01/01,22.00,DEPOSIT CHEQUES,,1368.43
		if ( $type =~ /^DEPOSIT CHEQUES$/ ) {
			print "$date: h. DEPOSIT CHEQUES '$who' $amt\n";
			$out .= "D$date\nP$who\nT$amt\nMn. Cheque - $who ($total)\n^\n";
			next;
		}

		# o. 01/01/01,22.00,DEPOSIT CHEQUES,,1368.43
		#if ( $type =~ /^DEPOSIT CHEQUES$/ ) {
		#	print "$date: h. DEPOSIT CHEQUES '$who' $amt\n";
		#	$out .= "D$date\nP$who\nT$amt\nMn. Cheque - $who ($total)\n^\n";
		#	next;
		#}
		
		# 100. UNKNOWN:
		if ( length $buf > 0 ) {
			print "Unknown entry:\n-----------\n$date,$amt,$type,$who,$cmt\n";
			die;
		}
	}
	else {
		print "Unknown entry:\n-----------\n$buf\n";
		die;
	}
}

# open output file
open( $outfile, "> $out_path" ) || Error("can't open output $!");
print $outfile "!Type:Bank\n";

#!Account\nNME Savings\n^\n";
print $outfile $out;
close $outfile;

#system 'D:\Program Files\Microsoft Money\System\mnyimprt.exe',$out_path;

__END__
:endofperl
