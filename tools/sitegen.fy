( sitegen.fy — static site generator for fy docs )
( Converts docs/*.md to _site/*.html )
( Usage: fy tools/sitegen.fy )

( === Configuration === )
:: src-dir "docs" ;
:: out-dir "_site" ;

( === CSS === )
:: css "
*{box-sizing:border-box}
body{max-width:860px;margin:0 auto;padding:2em;font-family:system-ui,-apple-system,sans-serif;line-height:1.6;color:#1a1a2e;background:#fafafa}
nav{margin-bottom:2em;padding:1em;background:#fff;border-radius:8px;border:1px solid #e0e0e0}
nav a{color:#3a5a9f;text-decoration:none;margin-right:1em}
nav a:hover{text-decoration:underline}
nav a.active{font-weight:bold;color:#1a1a2e}
main{background:#fff;padding:2em;border-radius:8px;border:1px solid #e0e0e0}
h1,h2,h3,h4,h5,h6{color:#1a1a2e;margin-top:1.5em;margin-bottom:0.5em}
h1{border-bottom:2px solid #e0e0e0;padding-bottom:0.3em}
code{background:#f0f0f0;padding:0.15em 0.4em;border-radius:3px;font-size:0.9em}
pre{background:#1a1a2e;color:#e0e0e0;padding:1em;border-radius:8px;overflow-x:auto;line-height:1.4}
pre code{background:none;padding:0;color:inherit}
table{border-collapse:collapse;width:100%;margin:1em 0}
th,td{border:1px solid #e0e0e0;padding:0.5em 0.8em;text-align:left}
th{background:#f0f0f0;font-weight:600}
tr:nth-child(even){background:#f9f9f9}
a{color:#3a5a9f}
ul,ol{padding-left:1.5em}
li{margin:0.3em 0}
hr{border:none;border-top:2px solid #e0e0e0;margin:2em 0}
" ;

( === HTML template === )
: template [ | title content nav |
  "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>"
  title s+ " - fy</title>\n<style>" s+ css s+ "</style>\n</head>\n<body>\n<nav>" s+
  nav s+ "</nav>\n<main>\n" s+
  content s+ "\n</main>\n</body>\n</html>\n" s+
] do ;

( === HTML escaping === )
: html-esc
  "&" "&amp;" sreplace
  "<" "&lt;" sreplace
  ">" "&gt;" sreplace
;

( === Inline formatting === )
( All inline processors: s -- s' )
( They use stack-based iteration with [cond] [body] repeat )

( Process backtick code spans: `code` -> <code>code</code> )
: code-span
  "" swap ( acc rest )
  [ dup "`" sfind dup 0 < not ] [
    ( acc rest pos )
    over 0 2 pick ssub     ( acc rest pos prefix )
    3 pick swap s+         ( acc rest pos newacc )
    rot drop swap          ( newacc rest pos )
    1 + over slen over - ssub ( newacc after-tick )
    dup "`" sfind
    dup 0 < [
      ( no closing tick: put back and stop )
      drop "`" swap s+
    ] [
      ( newacc after pos2 )
      over 0 2 pick ssub   ( newacc after pos2 code-content )
      "<code>" swap s+ "</code>" s+
      3 pick swap s+       ( newacc after pos2 newacc2 )
      rot drop swap        ( newacc2 after pos2 )
      1 + over slen over - ssub ( newacc2 rest )
    ] ifte
  ] repeat
  s+
;

( Process **bold** -> <strong>bold</strong> )
: bold-span
  "" swap ( acc rest )
  [ dup "**" sfind dup 0 < not ] [
    ( acc rest pos )
    over 0 2 pick ssub
    3 pick swap s+ rot drop swap
    2 + over slen over - ssub ( newacc after-open-** )
    dup "**" sfind
    dup 0 < [
      drop "**" swap s+
    ] [
      over 0 2 pick ssub
      "<strong>" swap s+ "</strong>" s+
      3 pick swap s+ rot drop swap
      2 + over slen over - ssub
    ] ifte
  ] repeat
  s+
;

( Process [text](url) links )
: link-span
  "" swap ( acc rest )
  [ dup "[" sfind dup 0 < not ] [
    ( acc rest pos )
    over 0 2 pick ssub
    3 pick swap s+ rot drop swap
    1 + over slen over - ssub ( newacc after-[ )
    dup "](" sfind
    dup 0 < [
      ( no close bracket: put [ back and bail )
      drop "[" swap s+
    ] [
      ( newacc after-[ linkclose-pos )
      over 0 2 pick ssub ( link-text )
      rot swap ( newacc link-text after-[ linkclose-pos )
      drop ( newacc link-text after-[ )
      dup "](" sfind 2 + over slen over - ssub ( after-bracket-paren )
      dup ")" sfind
      dup 0 < [
        ( no close-paren: reconstruct and bail )
        drop rot swap "[" swap s+ "](" s+ swap s+ ( newacc rest' )
      ] [
        ( after-paren-start paren-pos )
        over 0 2 pick ssub ( url )
        ( fix .md links to .html )
        dup ".md)" sends [ ".md" ".html" sreplace ] [] ifte
        dup ".md#" sfind 0 < not [ ".md" ".html" sreplace ] [] ifte
        ( stack: newacc linktext after-paren-start paren-pos url )
        rot swap 1 + over slen over - ssub ( newacc linktext url rest )
        rot rot ( newacc rest linktext url )
        swap "<a href=\"" swap s+ "\">" s+ swap s+ "</a>" s+ ( newacc rest link-html )
        rot swap s+ swap ( newacc' rest )
      ] ifte
    ] ifte
  ] repeat
  s+
;

( Full inline processing pipeline )
: process-inline
  html-esc
  code-span
  bold-span
  link-span
;

( === Parser state === )
( Use a struct for mutable state )
struct: PState
  i64 mode    ( 0=normal 1=code 2=para 3=list 4=table )
  i64 tbl     ( table header done flag )
;
:: ps PState.alloc ;
: ps-mode ps PState.mode@ nip ;
: ps-mode! ps PState.mode! drop ;
: ps-tbl ps PState.tbl@ nip ;
: ps-tbl! ps PState.tbl! drop ;
: ps-reset 0 ps-mode! 0 ps-tbl! ;

( Close current block )
: close-block
  ps-mode
  dup 2 = [ drop "</p>\n" ] [
  dup 3 = [ drop "</ul>\n" ] [
  dup 4 = [ drop "</tbody></table>\n" ] [
  drop ""
  ] ifte ] ifte ] ifte
  0 ps-mode!
;

( === Block-level parsing === )

( Heading level: count leading # chars )
: heading-level
  dup "######" sstarts [ drop 6 ] [
  dup "#####" sstarts [ drop 5 ] [
  dup "####" sstarts [ drop 4 ] [
  dup "###" sstarts [ drop 3 ] [
  dup "##" sstarts [ drop 2 ] [
  dup "#" sstarts [ drop 1 ] [
  drop 0
  ] ifte ] ifte ] ifte ] ifte ] ifte ] ifte
;

( Render heading with level: acc line -- acc' )
: render-heading [ | acc line |
  line heading-level [ | lvl |
    acc close-block s+
    "<h" s+ lvl i>s s+ ">" s+
    line lvl 1 + line slen lvl 1 + - ssub strim process-inline s+
    "</h" s+ lvl i>s s+ ">\n" s+
  ] do
] do ;

( Table header row: |col|col| -> <thead><tr><th>...</th></tr></thead> )
: table-header
  "|" ssplit
  "<thead><tr>" swap
  [
    strim dup slen 0 = [ drop ] [
      swap "<th>" s+ swap process-inline s+ "</th>" s+
    ] ifte
  ] each
  "</tr></thead><tbody>\n" s+
;

( Table data row )
: table-row
  "|" ssplit
  "<tr>" swap
  [
    strim dup slen 0 = [ drop ] [
      swap "<td>" s+ swap process-inline s+ "</td>" s+
    ] ifte
  ] each
  "</tr>\n" s+
;

( Check if line is table separator |---|---| )
: table-sep?
  strim dup "|" sstarts [ "-" sfind 0 < not ] [ drop 0 ] ifte
;

( Parse one line: acc line -- acc' )
: parse-line [ | acc line |
  ps-mode 1 = [
    ( Inside code block )
    line "```" sstarts [
      acc "</code></pre>\n" s+ 0 ps-mode!
    ] [
      acc line html-esc s+ "\n" s+
    ] ifte
  ] [
    line slen 0 = [
      ( Blank line: close block )
      acc close-block s+
    ] [
    line "```" sstarts [
      ( Open code block )
      acc close-block s+
      line 3 line slen 3 - ssub strim
      dup slen 0 = [ drop "<pre><code>" s+ ] [
        "<pre><code class=\"language-" swap s+ "\">" s+
      ] ifte
      1 ps-mode!
    ] [
    line heading-level 0 > [
      acc line render-heading
    ] [
    line "---" s= [
      acc close-block s+ "<hr>\n" s+
    ] [
    line "- " sstarts [
      ps-mode 3 = not [ acc close-block s+ "<ul>\n" s+ 3 ps-mode! ] [ acc ] ifte
      line 2 line slen 2 - ssub process-inline
      swap "<li>" s+ swap s+ "</li>\n" s+
    ] [
    line "|" sstarts [
      line table-sep? [
        acc ( skip separator, return acc unchanged )
      ] [
        ps-mode 4 = not [
          acc close-block s+ "<table>\n" s+ 4 ps-mode! 1 ps-tbl!
          line table-header s+
        ] [
          acc line table-row s+
        ] ifte
      ] ifte
    ] [
      ( Paragraph text )
      ps-mode 2 = not [
        acc close-block s+ "<p>" s+ line process-inline s+ 2 ps-mode!
      ] [
        acc " " s+ line process-inline s+
      ] ifte
    ] ifte ] ifte ] ifte ] ifte ] ifte ] ifte ] ifte
  ] ifte
] do ;

( Convert markdown to HTML )
: md>html
  ps-reset
  slines "" swap [ swap parse-line ] each
  close-block s+
;

( === Navigation === )
: build-nav [ | files |
  "" files
  [
    [ | nav filename |
      filename ".md" "" sreplace [ | stem |
        nav "<a href=\"" s+ stem ".html" s+ s+ "\">" s+
        stem "README" s= [ "Home" ] [ stem ] ifte
        s+ "</a> " s+
      ] do
    ] do
  ] each
] do ;

( === Title extraction === )
: extract-title
  slines
  dup qempty? [ drop "Untitled" ] [
    qhead
    dup "# " sstarts [
      2 over slen 2 - ssub strim
    ] [ drop "Untitled" ] ifte
  ] ifte
;

( Strip breadcrumb nav line from docs pages )
: strip-breadcrumb
  slines
  dup qlen 2 > [
    dup 1 qnth
    dup "[Home]" sstarts swap "| **" sfind 0 < not [ 1 ] [ 0 ] ifte [ 1 ] [ 0 ] ifte [
      dup qhead swap qtail
      dup qempty? not [ dup qhead slen 0 = [ qtail ] [] ifte ] [] ifte
      swap qnil swap qpush swap cat
    ] [] ifte
  ] [] ifte
  "" swap [ swap "\n" s+ swap s+ ] each
;

( === File processing === )
: process-file [ | filename nav |
  src-dir "/" s+ filename s+ slurp [ | content |
    content strip-breadcrumb [ | clean |
      clean extract-title [ | title |
        title clean md>html nav template [ | html |
          out-dir "/" s+ filename ".md" ".html" sreplace s+ html swap spit drop
        ] do
      ] do
    ] do
  ] do
] do ;

( === Main === )
out-dir mkdir-p drop

src-dir dir-list
[ ".md" sends ] filter

dup build-nav

swap
[ over swap process-file ] each
drop

"\nSite generated in " swrite out-dir swrite "/\n" swrite
