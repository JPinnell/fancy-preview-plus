#!/usr/bin/env perl
# Fixed version of fancy-preview
# -- Updated by Jonathan Pinnell to improve biblatex citation tooltips --
# -- Ghostscript compression added by Gemini --

use strict;
use warnings;
use Getopt::Long;

# --- User Configuration Section ---
#
# Adjust these variables to change the appearance of the tooltips.
#
# Colors can be any color defined by the LaTeX xcolor package.
# Examples: "red", "blue!50", "green!20!black", "olive"
my $tooltip_bg_color     = "blue!7";
my $tooltip_border_color = "black!60";
my $tooltip_scale = 1.0;

# --- Ghostscript Compression Settings ---
# Set to 1 to enable PDF compression with Ghostscript.
# This can significantly reduce the size of the final PDF with tooltips.
# Requires Ghostscript to be installed and in your system's PATH.
my $use_ghostscript = 1;

# The command to run Ghostscript. 'gs' is common for Linux/macOS.
# Windows users might need 'gswin64c' or 'gswin32c'.
my $ghostscript_cmd = "gswin64c";

# Ghostscript options for compression. /ebook is a good balance.
# Other options: /screen (smaller), /printer, /prepress (larger).
my $ghostscript_options = "-sDEVICE=pdfwrite -dPDFSETTINGS=/ebook -dNOPAUSE -dQUIET -dBATCH";

# --- End of User Configuration Section ---


my $filename = $ARGV[0];
my $filename_noext = $filename;
$filename_noext =~ s/\.tex//;
my $aux_file=$filename_noext.".aux";
my @tempfilenames=($filename_noext.".aux");
my %latex =();

# Setting for two passes of preview.sty
$latex{'a'}='\makeatletter\def\nononotags{\def\@eqnnum{\relax}\def\tagform@##1{}}\makeatother\AtBeginDocument{\usepackage[pdftex,active,tightpage,displaymath]{preview}\nononotags}';
$latex{'b'}='\AtEndDocument{\clearpage}\AtBeginDocument{\usepackage[pdftex,active,tightpage]{preview}\setlength\PreviewBorder{5pt}}';

# Do not use third pass of preview.sty by default
$latex{'c'}='';
$latex{'a_extra'}='';
$latex{'b_extra'}='';
my $pass_order = "";

# Hacks to get references (in the first pass).
$latex{'preview_bibitem'}='\AtBeginDocument{\newenvironment{fakebibitem}{\begin{minipage}{0.75\textwidth}}{\end{minipage}}\PreviewEnvironment{fakebibitem}\renewcommand\bibitem[2][]{\BIBITEM {#2}}\def\BIBITEM#1#2\par{\begin{fakebibitem} #2 \label{fancy:cite:#1}\end{fakebibitem}}}';

# The environments for extraction in the second pass of preview.sty.
$latex{'environments'}="Theorem,theorem,lemma,corollary,definition";
$latex{'snarfenvironments'}="figure,table"; # Added table

# The variable with initial commands for all pdflatex calls.
$latex{'ini'}='\\relax';
my $pdflatex="pdflatex";
my $bibtex="biber";
my $pdfcrop="pdfcrop";

# Default options for final compilation with fancytooltips.
my $fancy_options="previewall,nosoap";
my $tooltipfile="";
my $help=0;
my $version=0;
my $date="24.6.2012";
my $versionnumber="3.2-final-gs"; # Updated version number

# The code used in preamble
$latex{'tooltips_envelope_preamble'}='\usepackage{xcolor,tikz}\usetikzlibrary{shadows}\def\tooltipwraper#1{\begin{tikzpicture}\node[drop shadow,fill=' . $tooltip_bg_color . ',draw=' . $tooltip_border_color . ', rounded corners=3pt,very thick]{#1};\end{tikzpicture}}';

# --- This is the robust method for applying the tooltip to the final document ---
$latex{'biblatex'}='
\newtoggle{inbib}
\AtBeginBibliography{\toggletrue{inbib}}
\DeclareFieldFormat{bibhyperref}{%
  \iftoggle{inbib}
    {\bibhyperref{#1}}
    {\tooltip*{\bibhyperref{#1}}{fancy:cite:\thefield{entrykey}}}%
}
';

my %options=();
my $tooltip_types = "all"; # Default to all
GetOptions (
"fancy_options=s"   => \$options{fancy_options},
"pdfcrop=s"   => \$options{pdfcrop},
"tooltips=s"   => \$options{tooltips},
"ini_file=s"   => \$options{ini_file},
"types=s"   => \$tooltip_types, # New option
"version"   => \$version,
"help"  =>  \$help);

# --- Parse --types option ---
my %enable_tooltips = (
    'citations' => 0,
    'equations' => 0,
    'figures'   => 0,
    'tables'    => 0,
    'theorems'  => 0 # Covers all theorem-like envs
);

if ($tooltip_types eq "all") {
    %enable_tooltips = map { $_ => 1 } keys %enable_tooltips;
} else {
    my @types = split(/,/, $tooltip_types);
    foreach my $type (@types) {
        $type =~ s/^\s+|\s+$//g; # trim whitespace
        if (exists $enable_tooltips{$type}) {
            $enable_tooltips{$type} = 1;
        }
    }
}

print "Enabled tooltips for: ";
print join(", ", grep { $enable_tooltips{$_} } keys %enable_tooltips);
print "\n\n";

if ($version)
{
    print "$versionnumber\n";
    exit();
}

if ($help)
{
    my $help_text='
This is fancy-preview script (R. Marik, http://user.mendelu.cz/marik)
VERSION 3.2 (Fixed, Enhanced, and Compressed by Jonathan Pinnell & Gemini)
==========================================================================

The script converts LaTeX files into PDF files with interactive tooltips
for citations, equations, figures, and more.

NEW FEATURE: --types
--------------------
You can now specify which tooltips to generate using the --types flag.
Provide a comma-separated list of desired types. If omitted, all types
are generated.

Available types: citations, equations, figures, tables, theorems

NEW FEATURE: Ghostscript Compression
-----------------------------------
If enabled in the script, Ghostscript is used to compress the tooltip
previews, which can significantly reduce the final PDF\'s file size.
You can configure this in the User Configuration Section of the script.

EXAMPLES:
  # Compile all tooltips (default)
  perl fancy_preview_updated.pl yourfile.tex

  # Compile ONLY citations
  perl fancy_preview_updated.pl yourfile.tex --types="citations"

  # Compile citations, figures, and tables
  perl fancy_preview_updated.pl yourfile.tex --types="citations,figures,tables"

';
    print $help_text;
    exit();
}

#### Read configuration from ~/.fancy-preview.ini and ./fancy-preview.ini
eval {
    require Config::IniFiles;
    Config::IniFiles->import();
};
if ($@) {
    print "Warning: Config::IniFiles not found. Using defaults.\n";
}

my($cfg);

sub set_tex_variable
{
    if ($cfg && $cfg->exists( 'latex', $_[0] )) {$latex{$_[0]}=$cfg->val( 'latex', $_[0]);}
}

sub read_config
{
    if ( -e $_[0] && defined &Config::IniFiles::new)
    {
	$cfg = Config::IniFiles->new( -file => $_[0]);
	if ($cfg->exists( 'main', 'pdfcrop' )) {$pdfcrop=$cfg->val( 'main', 'pdfcrop');}
	if ($cfg->exists( 'main', 'fancy_options' )) {$fancy_options=$cfg->val( 'main', 'fancy_options');}
	if ($cfg->exists( 'main', 'tooltips' )) {$tooltipfile=$cfg->val( 'main', 'tooltips');}
	my @options=("tooltips_envelope_preamble","environments","snarfenvironments","a","a_extra","b","b_extra","c","ini","biblatex");
	foreach my $current_option (@options) {set_tex_variable($current_option);}
    }
}

if ($options{ini_file})
{
    read_config($options{ini_file});
}
else
{
    read_config($ENV{"HOME"}."/.fancy-preview.ini") if $ENV{"HOME"};
    read_config("./fancy-preview.ini");
}
#### end of configuration

# command line overrides config file
if ($options{fancy_options}) {$fancy_options=$options{fancy_options}};
if ($options{pdfcrop}) {$pdfcrop=$options{pdfcrop}};
if ($options{tooltips}) {$tooltipfile=$options{tooltips}};

my $biblatex=0;

unlink ("$filename_noext.aux");

# The first compilation to create numbers for equations, theorems, figures, ...
print "Initial compilation...\n";
system("$pdflatex -interaction=nonstopmode \"$latex{ini} \\input $filename\"");

# We test if the file uses biblatex. If not, thebibliography is supposed.
open(LOG, $filename_noext.".log");
my @log_data=<LOG>;
my @log_tmp = grep /^Package: biblatex/, @log_data;
my $log_tmp_size=@log_tmp;
if ($log_tmp_size>0) {$biblatex=1;}
close(LOG);


# --- UNTANGLED COMPILATION PASSES ---

# --- PASS A (Equations) ---
if ($enable_tooltips{'equations'}) {
    print "Extracting equations (pass a)...\n";
    compile_parse_aux_file_and_crop("a");
    $pass_order .= "a";
}

# --- PASS B (Environments) ---
if ($enable_tooltips{'figures'} || $enable_tooltips{'theorems'} || $enable_tooltips{'tables'}) {
    if($latex{'environments'} ne "" && $enable_tooltips{'theorems'})
    {
        $latex{'b'}.='\AtBeginDocument{\PreviewEnvironment[{[]}]{'.join('}\PreviewEnvironment[{[]}]{',split(/,/,$latex{'environments'}))."}}";
    }
    if($latex{'snarfenvironments'} ne "" && ($enable_tooltips{'figures'} || $enable_tooltips{'tables'}))
    {
        $latex{'b'}.='\AtBeginDocument{\PreviewSnarfEnvironment[{[]}]{'.join('}\PreviewSnarfEnvironment[{[]}]{',split(/,/,$latex{'snarfenvironments'}))."}}";
    }
    $latex{'b'}.=$latex{'b_extra'};

    print "Extracting environments (pass b)...\n";
    compile_parse_aux_file_and_crop("b");
    $pass_order .= "b";
}


# --- PASS C (Custom) ---
if($latex{'c'} ne "")
{
    print "Additional extraction pass (pass c)...\n";
    compile_parse_aux_file_and_crop("c");
    $pass_order .= "c";
}

# --- PASS D (Citations) ---
if ($enable_tooltips{'citations'} && $biblatex) {
    print "Extracting citations (pass d)...\n";

    open(AUX, $aux_file);
    my @aux_data=<AUX>;
    my @result=();
    foreach my $a (@aux_data) {
        if ($a =~ m/\\abx\@aux\@cite\{[^}]*\}\{([^}]+)\}/) {
            my $citekey = $1;
            push(@result, "\\fancycitation{$citekey}\n");
        }
    }
    close(AUX);

    sub uniq { return keys %{{ map { $_ => 1 } @_ }}; }

    open(AUXA, ">$filename_noext"."-fancybib.tmp");
    foreach my $a (sort(uniq(@result))) { print AUXA $a; }
    close(AUXA);
    push (@tempfilenames,$filename_noext."-fancybib.tmp");

    $latex{'d'} = '\AtBeginDocument{'
               . '\usepackage[pdftex,active,tightpage]{preview}'
               . '\newenvironment{fakebibitem}{\begin{minipage}{0.8\linewidth}}{\end{minipage}}'
               . '\PreviewEnvironment{fakebibitem}'
               . '\def\fancycitation#1{\begin{fakebibitem}\fullcite{#1}\label{fancy:cite:#1}\end{fakebibitem}}'
               . '\renewcommand{\printbibliography}{\clearpage\input{' . $filename_noext . '-fancybib.tmp}\clearpage}'
               . '}';

    compile_parse_aux_file_and_crop("d");
    $pass_order .= "d";
}


print "\n----------------------------------------------\n------ Generating tooltips (creating minimal.pdf) ----------\n----------------------------------------------\n";

my $opt_pdfpages_a="";
my $opt_pdfpages_b="";

print "Using pass order: $pass_order\n";

my $inserttooltips='\insertttp{'.join('}\insertttp{',split(//,$pass_order)).'}';

if ($tooltipfile ne "")
{
    $opt_pdfpages_a='\usepackage{multido}';
    $opt_pdfpages_b='\ifx\pdfpagewrapper\undefined\let\pdfpagewrapper\relax\fi\pdfximage{'.$tooltipfile.'.pdf}\edef\FancyPreviewTotalPages{\the\pdflastximagepages}\multido{\i=1+1}{\FancyPreviewTotalPages}{\setbox0=\hbox{\pdfpagewrapper{\includegraphics[page=\i]{'.$tooltipfile.'.pdf}}}\pdfpagewidth=\wd0 \pdfpageheight=\ht0 \advance \pdfpageheight by \dp0 \copy0\newpage}\newpage';
}

open(my $minimal_tex, '>', 'minimal.tex') or die "Cannot create minimal.tex: $!";
# --- FEATURE: Use configurable scale for tooltip content ---
print $minimal_tex '\documentclass{minimal}
\usepackage{graphicx}'.$opt_pdfpages_a.'
\usepackage[papersize={5in,5in},margin=1pt]{geometry}'.$latex{'tooltips_envelope_preamble'}.'
\usepackage[createtips]{fancytooltips}
\newdimen\dist \dist=5pt\relax
\begin{document}
\pagestyle{empty}'.$opt_pdfpages_b.'
\relax
\gdef\savemaplabels#1#2#3#4{\xdef\temp{#2}}
\def\fancypreviewnewlabel#1#2{\savemaplabels#2
\expandafter\ifx\csname keytip:#1:used\endcsname\relax
\expandafter\def\csname keytip:#1:used\endcsname{used}
\setbox0=\vbox{\kern\dist\hbox{\kern\dist\tooltipwraper{\includegraphics[scale=' . $tooltip_scale . ', page=\temp]{'.$filename_noext.'-\ttpfilename-crop.pdf}}\kern\dist}\kern\dist}
\pdfpagewidth=\wd0
\pdfpageheight=\ht0
\advance \pdfpageheight by \dp0
\copy0
\keytip{#1}\newpage\fi}
\def\insertttp#1{\def\ttpfilename{#1}\input '.$filename_noext.'-#1.tmp}'.$inserttooltips.'
\end{document}';
close($minimal_tex);

print "Compiling minimal.tex to create minimal.pdf...\n";
my $minimal_result = system("$pdflatex -interaction=nonstopmode minimal.tex");

if ($minimal_result != 0 || !-e "minimal.pdf") {
    print "WARNING: Failed to create minimal.pdf properly.\n";
    print "Creating empty minimal.pdf as fallback...\n";
    open(my $empty_tex, '>', 'minimal-empty.tex');
    print $empty_tex '\documentclass{minimal}\begin{document}\mbox{}\end{document}';
    close($empty_tex);
    system("$pdflatex -interaction=nonstopmode minimal-empty.tex");
    rename("minimal-empty.pdf", "minimal.pdf") if -e "minimal-empty.pdf";
}

if (!-e "minimal.pdf") {
    die "ERROR: Could not create minimal.pdf. Cannot continue.\n";
}

print "minimal.pdf created successfully!\n";

# --- NEW: Ghostscript Compression Step ---
if ($use_ghostscript) {
    if (-e "minimal.pdf") {
        print "Attempting to compress minimal.pdf with Ghostscript...\n";
        my $compressed_file = "minimal-compressed.pdf";
        my $gs_command = "$ghostscript_cmd $ghostscript_options -sOutputFile=$compressed_file minimal.pdf";
        my $gs_result = system($gs_command);

        if ($gs_result == 0 && -e $compressed_file && -s $compressed_file > 0) {
            my $original_size = -s "minimal.pdf";
            my $compressed_size = -s $compressed_file;
            my $reduction = $original_size > 0 ? (1 - $compressed_size / $original_size) * 100 : 0;
            printf("Compression successful! Size reduced from %.2f KB to %.2f KB (%.1f%% reduction).\n", $original_size / 1024, $compressed_size / 1024, $reduction);
            unlink("minimal.pdf");
            rename($compressed_file, "minimal.pdf");
        } else {
            print "WARNING: Ghostscript compression failed or produced an empty file. Using the uncompressed version.\n";
            unlink($compressed_file) if -e $compressed_file; # Clean up failed attempt
        }
    }
}
# --- End of Ghostscript Step ---


if ($tooltipfile ne "")
{
    open(TIPS1, ">>minimal.tips");
    if (-e "$tooltipfile.tips") {
        open(TIPS2, "$tooltipfile.tips");
        while (<TIPS2>) { print TIPS1 $_; }
        close (TIPS2);
    }
    close (TIPS1);
}

if (!-e "minimal.tips") {
    open(my $tips, '>', 'minimal.tips');
    close($tips);
}

$latex{'ini'}='\\relax';
if ($biblatex && $enable_tooltips{'citations'})
{
    open(BIBL, ">fancy-preview-biblatex-settings.tex");
    print BIBL $latex{'biblatex'};
    close (BIBL);
    push (@tempfilenames,"fancy-preview-biblatex-settings.tex");
    $latex{'ini'}='\AtBeginDocument{\input fancy-preview-biblatex-settings.tex}';
}

# Final compilation passes
for my $i (1 .. 4){
    my $hypersetup='\hypersetup{colorlinks=true}';
    print  "----------------------------------------------\n------ Final compilation $i of 4 ----------\n----------------------------------------------\n";
    my $final_command = "$pdflatex -interaction=nonstopmode -jobname=$filename_noext \"";
    $final_command .= $latex{'ini'} if $latex{'ini'} ne '\\relax';
    $final_command .= '\RequirePackage{etoolbox}\PassOptionsToPackage{active,mouseover,movetips,filename=minimal,'.$fancy_options.'}{fancytooltips}\AtEndPreamble{\usepackage{fancytooltips}'.$hypersetup.'}\input '.$filename.'"';
    system($final_command);
}

# Cleanup
foreach my $deletefile (@tempfilenames) {unlink ($deletefile);}
unlink("minimal.tex");
unlink("minimal-empty.tex") if -e "minimal-empty.tex";
unlink("minimal-compressed.pdf") if -e "minimal-compressed.pdf";

print "\n ---------------------------------------------\n";
print " fancy-preview with options \"$fancy_options\" on \"$filename\" finished\n";
print " The output is in $filename_noext.pdf\n";
print " ---------------------------------------------\n\n";

sub parse_aux_file_and_crop
{
    if (! -e "$filename_noext.pdf") {
        print "!!! WARNING: $filename_noext.pdf not found. Skipping parse_aux_file_and_crop for pass $_[0].\n";
        return;
    }
    open(AUX, $aux_file);
    my @aux_data=<AUX>;
    my @filtered_data_tmp = grep {/\\newlabel/} @aux_data;
    my @filtered_data = grep {!/tocindent/} @filtered_data_tmp;
    my $aux_file_a=$filename_noext."-".$_[0].".tmp";
    open(AUXA, ">$aux_file_a");
    foreach my $aa (@filtered_data)
    {
	    $aa =~ s/\\newlabel\{/\\fancypreviewnewlabel\{/;
	    print AUXA $aa;
    }
    close (AUXA);
    close (AUX);
    push(@tempfilenames,$aux_file_a);
    print "Cropping PDF file (pass $_[0])...\n";
    system("$pdfcrop $filename_noext.pdf $filename_noext-$_[0]-crop.pdf");
    push(@tempfilenames,"$filename_noext-$_[0]-crop.pdf");
}

sub compile_parse_aux_file_and_crop
{
    my $pass = $_[0];
    unlink ("$filename_noext.aux");
    system("$pdflatex -interaction=nonstopmode \"$latex{ini} \\input $filename\"");
    optbibtex();
    my $command = "$pdflatex -interaction=nonstopmode \"$latex{ini} $latex{$pass} \\input $filename\"";
    system($command);
    parse_aux_file_and_crop($pass);
}

sub optbibtex
{
    if ($biblatex)
    {
        print "Running biber for biblatex...\n";
        system("biber $filename_noext");
        system("$pdflatex -interaction=nonstopmode \"$latex{ini} \\input $filename\"");
    }
}