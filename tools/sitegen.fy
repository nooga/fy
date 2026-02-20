( sitegen.fy — static site generator for fy docs )
( Architecture: parse markdown → executable quote → do → HTML )
( Usage: fy tools/sitegen.fy )

( === HTML escaping === )
: html-esc
  "&" "&amp;" sreplace
  "<" "&lt;" sreplace
  ">" "&gt;" sreplace
;

( === Emission words === )

: .h [ | text lvl |
  "<h" lvl i>s s+ ">" s+ text s+ "</h" s+ lvl i>s s+ ">\n" s+
] do ;

: .p "<p>" swap s+ "</p>\n" s+ ;

: .hr "<hr>\n" ;

: .pre [ | content lang |
  lang slen 0 > [
    "<pre><code class=\"language-" lang s+ "\">" s+ content s+ "</code></pre>\n" s+
  ] [
    "<pre><code>" content s+ "</code></pre>\n" s+
  ] ifte
] do ;

: .code "<code>" swap s+ "</code>" s+ ;

: .strong "<strong>" swap s+ "</strong>" s+ ;

: .a [ | text url |
  "<a href=\"" url s+ "\">" s+ text s+ "</a>" s+
] do ;

: .li "<li>" swap s+ "</li>\n" s+ ;

: .ul "<ul>\n" swap s+ "</ul>\n" s+ ;

( === Quote building helpers === )
: q, qpush ;
: q+ q, \s+ qpush ;

( === Inline parser === )
( min-pos: pick minimum non-negative value, treat negatives as infinity )
( a b -- min )
: min-pos
  over 0 < [ swap drop ] [
    dup 0 < [ drop ] [
      over over > [ swap ] then drop
    ] ifte
  ] ifte
;

( Parse inline markdown formatting, returns HTML string )
( Finds leftmost marker, processes it, recurses on the rest )
: parse-inline [ | s |
  s slen 0 = [ "" ] [
    s "`" sfind s "**" sfind min-pos s "[" sfind min-pos
    dup 0 < [
      ( no markers found )
      drop s html-esc
    ] [ [ | pos |
      s 0 pos ssub html-esc ( prefix )
      s pos 1 ssub "`" s= [
        ( --- code span --- )
        s pos 1 + s slen pos 1 + - ssub [ | after |
          after "`" sfind dup 0 < [
            drop "`" after parse-inline s+
          ] [ [ | end |
            after 0 end ssub html-esc .code
            after end 1 + after slen end 1 + - ssub parse-inline s+
          ] do ] ifte
        ] do
      ] [
        s pos 2 ssub "**" s= [
          ( --- bold --- )
          s pos 2 + s slen pos 2 + - ssub [ | after |
            after "**" sfind dup 0 < [
              drop "**" after parse-inline s+
            ] [ [ | end |
              after 0 end ssub parse-inline .strong
              after end 2 + after slen end 2 + - ssub parse-inline s+
            ] do ] ifte
          ] do
        ] [
          ( --- link [text](url) --- )
          s pos 1 + s slen pos 1 + - ssub [ | after |
            after "](" sfind dup 0 < [
              drop "[" after parse-inline s+
            ] [ [ | bpos |
              after 0 bpos ssub parse-inline ( link text )
              after bpos 2 + after slen bpos 2 + - ssub [ | urlrest |
                urlrest ")" sfind dup 0 < [
                  drop ( unmatched paren )
                  "[" after parse-inline s+
                ] [ [ | epos |
                  urlrest 0 epos ssub ( url )
                  ( rewrite .md -> .html, handle .md#fragment too )
                  dup ".md" sfind dup 0 < [ drop ] [
                    [ | url mdpos |
                      url 0 mdpos ssub ".html" s+ url mdpos 3 + url slen mdpos 3 + - ssub s+
                    ] do
                  ] ifte
                  .a
                  urlrest epos 1 + urlrest slen epos 1 + - ssub parse-inline s+
                ] do ] ifte
              ] do
            ] do ] ifte
          ] do
        ] ifte
      ] ifte
      s+ ( prefix + result )
    ] do ] ifte
  ] ifte
] do ;

( === Heading level === )
: heading-level
  [ ["######" sstarts] [6]
    ["#####" sstarts]  [5]
    ["####" sstarts]   [4]
    ["###" sstarts]    [3]
    ["##" sstarts]     [2]
    ["#" sstarts]      [1]
    [0]
  ] cond
;

( === Block parser helpers === )

( Flush paragraph: q para -- q' )
: flush-para
  dup slen 0 > [
    parse-inline q, \.p qpush \s+ qpush
  ] [
    drop
  ] ifte
;

( Flush code block: q cbuf clang -- q' )
: flush-code [ | q buf lang |
  buf slen 0 > [
    q buf html-esc q, lang q, \.pre qpush \s+ qpush
  ] [ q ] ifte
] do ;

( Collect consecutive "- " lines into HTML list items )
( lines acc -- lines' acc' )
: collect-li
  over qempty? [
    ( empty queue, return as-is )
  ] [
    over qhead "- " sstarts [
      over qhead [ | line |
        swap qtail swap
        line 2 line slen 2 - ssub parse-inline .li s+
        collect-li
      ] do
    ] then
  ] ifte
;

( Split table row respecting \| escapes )
( s -- cells )
: table-split
  "\\|" "\0" sreplace "|" ssplit [ "\0" "|" sreplace ] map
;

( Build table cells from a split row )
( cells is-header -- html )
: build-cells [ | cells hdr |
  cells qempty? [ "" ] [
    cells qhead strim parse-inline
    hdr [ "<th>" swap s+ "</th>" s+ ] [ "<td>" swap s+ "</td>" s+ ] ifte
    cells qtail hdr build-cells s+
  ] ifte
] do ;

( Collect consecutive "|" lines and build table HTML )
( lines acc row# -- lines' html )
: collect-tr [ | lines acc rownum |
  lines qempty? [ lines acc ] [
    lines qhead "|" sstarts not [ lines acc ] [
      lines qhead 1 lines qhead slen 2 - ssub table-split
      dup qhead strim "-" sstarts [
        ( separator row - skip )
        drop lines qtail acc rownum collect-tr
      ] [
        ( data/header row - build cells directly on stack )
        rownum 1 = build-cells
        "<tr>" swap s+ "</tr>\n" s+
        acc swap s+ lines qtail swap rownum 1 + collect-tr
      ] ifte
    ] ifte
  ] ifte
] do ;

( === Recursive block parser === )
( q lines mode cbuf clang pbuf -- q' )
( mode: 0=normal, 1=code )
: parse-lines [ | q lines mode cbuf clang pbuf |
  lines qempty? [
    ( EOF: flush remaining state )
    mode 1 = [
      q cbuf clang flush-code
    ] [
      q pbuf flush-para
    ] ifte
  ] [
    lines qhead lines qtail [ | line rest |
      mode 1 = [
        ( === code mode === )
        line "```" sstarts [
          ( close code block )
          q cbuf clang flush-code
          rest 0 "" "" "" parse-lines
        ] [
          ( accumulate code line )
          q rest 1
          cbuf slen 0 > [ cbuf "\n" s+ line s+ ] [ line ] ifte
          clang pbuf parse-lines
        ] ifte
      ] [
        ( === normal mode === )
        line slen 0 = [
          ( blank line: flush paragraph )
          q pbuf flush-para
          rest 0 cbuf clang "" parse-lines
        ] [
          line "- " sstarts [
            ( list: flush paragraph, collect all consecutive list items )
            q pbuf flush-para [ | q2 |
              lines "" collect-li [ | rest2 html |
                q2 html .ul q, \s+ qpush
                rest2 0 cbuf clang "" parse-lines
              ] do
            ] do
          ] [
            line "|" sstarts [
              ( table: flush paragraph, collect all consecutive table rows )
              q pbuf flush-para [ | q2 |
                lines "" 1 collect-tr [ | rest2 html |
                  q2 "<table>\n" html s+ "</table>\n" s+ q, \s+ qpush
                  rest2 0 cbuf clang "" parse-lines
                ] do
              ] do
            ] [
              line heading-level [ | lvl |
                lvl 0 > [
                  ( heading )
                  q pbuf flush-para
                  line lvl 1 + line slen lvl 1 + - ssub strim parse-inline q,
                  lvl q, \.h qpush \s+ qpush
                  rest 0 cbuf clang "" parse-lines
                ] [
                  line "```" sstarts [
                    ( open code fence )
                    q pbuf flush-para
                    rest 1 ""
                    line 3 line slen 3 - ssub strim
                    "" parse-lines
                  ] [
                    line "---" s= [
                      ( horizontal rule )
                      q pbuf flush-para
                      \.hr qpush \s+ qpush
                      rest 0 cbuf clang "" parse-lines
                    ] [
                      ( paragraph text: accumulate )
                      q rest 0 cbuf clang
                      pbuf slen 0 > [ pbuf " " s+ line s+ ] [ line ] ifte
                      parse-lines
                    ] ifte
                  ] ifte
                ] ifte
              ] do
            ] ifte
          ] ifte
        ] ifte
      ] ifte
    ] do
  ] ifte
] do ;

( Entry point: lines -- quote )
: parse-blocks
  qnil "" q,  ( start with [""] )
  swap 0 "" "" "" parse-lines
;

( === Title extraction === )
( Extract title from first # heading line )
( lines -- title )
: extract-title [ | lines |
  lines qempty? [ "Untitled" ] [
    lines qhead "# " sstarts [
      lines qhead 2 lines qhead slen 2 - ssub strim
    ] [
      lines qtail extract-title
    ] ifte
  ] ifte
] do ;

( Is this line a nav breadcrumb? )
( line -- flag )
: nav-line?
  dup dup "[" sstarts swap "**" sstarts or not [ drop 0 ] [
    "|" sfind 0 >
  ] ifte
;

( Remove nav breadcrumb lines from content )
( lines -- lines' )
: strip-nav [ nav-line? not ] filter ;

( === HTML template === )
( Color palette from raylib_synth_poly.fy )
( BG: #010101  FG: #B4AFA5  AMBER: #FFB000 )

: page-css
  "*{box-sizing:border-box}"
  "body{background:#010101;color:#d4d0c8;font-family:sans-serif;padding:0;margin:0;overflow-x:hidden}" s+
  "::selection{background:#FFB000;color:#010101}" s+
  "main{padding:0 45px 45px 45px;max-width:900px}" s+
  "main>*{max-width:900px;margin-bottom:30px}" s+
  "h1{font-size:24px;color:#fff;margin-bottom:10px}" s+
  "h2{font-size:20px;color:#fff;margin-top:2rem}" s+
  "h3{font-size:16px;color:#fff}" s+
  "p{line-height:25px;font-size:16px;margin-top:0;max-width:700px}" s+
  "a{color:#d4d0c8;text-decoration:underline}" s+
  "a:hover{color:#FFB000}" s+
  "code{background:#1a1a18;padding:2px 5px;font-family:monospace;font-size:.9em;border-radius:2px;color:#FFB000}" s+
  "pre{max-width:700px;background:#1a1a18;padding:15px;overflow-x:auto;margin-bottom:30px}" s+
  "pre code{background:none;padding:0;color:#B4AFA5;display:block;white-space:pre;font-size:14px}" s+
  "table{max-width:700px;margin-bottom:30px;border-collapse:collapse;border:1px solid #1a1a18}" s+
  "th,td{border:1px solid #1a1a18;padding:5px 15px;vertical-align:top;text-align:left}" s+
  "th{font-weight:bold;color:#d4d0c8}" s+
  "ul{line-height:25px;max-width:700px;padding-left:1.5rem;margin:0 0 30px 0}" s+
  "li{margin:.25rem 0}" s+
  "hr{border:none;border-top:1px solid #B4AFA5;margin:2rem 0;clear:both}" s+
  "nav{padding:20px 45px;max-width:900px;margin-top:30px;margin-bottom:10px}" s+
  "nav a{margin-right:15px;text-decoration:none;color:#B4AFA5}" s+
  "nav a:hover{color:#FFB000}" s+
  "nav a.active{color:#FFB000}" s+
  "strong{color:#d4d0c8}" s+
  "@media only screen and (max-width:900px){main{padding:20px}nav{padding:20px}}" s+
;

( Emit a nav link, marking active page )
( acc href label current-href -- acc' )
: nav-link [ | acc href label cur |
  acc "<a href=\"" s+ href s+ "\""  s+
  href cur s= [ " class=\"active\"" s+ ] then
  ">" s+ label s+ "</a>" s+
] do ;

( title body html-name -- html )
: wrap-page [ | title body name |
  "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"
  "<meta charset=\"utf-8\">\n" s+
  "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n" s+
  "<title>" s+ title s+ " - fy</title>\n" s+
  "<style>" s+ page-css s+ "</style>\n" s+
  "</head>\n<body>\n<nav>" s+
  "README.html" "Home" name nav-link
  "getting-started.html" "Getting Started" name nav-link
  "language-guide.html" "Language Guide" name nav-link
  "builtins.html" "Builtins" name nav-link
  "ffi.html" "FFI" name nav-link
  "macros.html" "Macros" name nav-link
  "examples.html" "Examples" name nav-link
  "</nav>\n<main>\n" s+
  body s+
  "</main>\n</body>\n</html>\n" s+
] do ;

( === File processing === )
( Convert a .md filename to .html )
( path -- html-name )
: md>html
  dup slen 3 - 0 swap ssub ".html" s+
;

( Process a single markdown file )
( src-dir out-dir filename -- )
: process-file [ | src out name |
  src "/" s+ name s+ slurp [ | content |
    content slines [ | lines |
      lines extract-title [ | title |
        lines strip-nav parse-blocks do [ | body |
          name md>html [ | htmlname |
            title body htmlname wrap-page [ | html |
              out "/" s+ htmlname s+ [ | dest |
                html dest spit drop
                "  " swrite name swrite " -> " swrite dest swrite "\n" swrite
              ] do
            ] do
          ] do
        ] do
      ] do
    ] do
  ] do
] do ;

( === Main === )
"docs" "build" [ | src out |
  out mkdir-p drop
  "Building site from " swrite src swrite " to " swrite out swrite "...\n" swrite
  src dir-list [ | files |
    files [
      dup ".md" sends [
        src out rot process-file
      ] [ drop ] ifte
    ] each drop
  ] do
  "Done.\n" swrite
] do
