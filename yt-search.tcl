#!/usr/bin/env tclsh

# yt-search.tcl
# YouTube search utility for Tcl using YouTube Data API v3.

set yt_search_version "0.2.0"

proc url_encode {s} {
    set out ""
    set len [string length $s]
    for {set i 0} {$i < $len} {incr i} {
        set ch [string index $s $i]
        set code [scan $ch %c]
        if {($code >= 48 && $code <= 57) || ($code >= 65 && $code <= 90) || ($code >= 97 && $code <= 122) || $ch in {"-" "_" "." "~"}} {
            append out $ch
        } elseif {$ch eq " "} {
            append out "%20"
        } else {
            append out %[format %02X $code]
        }
    }
    return $out
}

proc json_unescape_basic {s} {
    set out $s
    regsub -all {\\n} $out "\n" out
    regsub -all {\\r} $out "\r" out
    regsub -all {\\t} $out "\t" out
    regsub -all {\\"} $out "\"" out
    regsub -all {\\\\} $out "\\" out
    return $out
}

proc parse_search_results {json} {
    set results {}
    
    # Simple approach: find all videoId and title pairs
    # Look for "videoId": "..." and then "title": "..."
    
    set videoid_pattern {videoId['"]\s*:\s*['"](.*?)['"]}
    set title_pattern {title['"]\s*:\s*['"](.*?)['"]}
    
    # Extract all videoIds first
    set videoIds {}
    set pos 0
    while {[regexp -start $pos -indices $videoid_pattern $json match] != 0} {
        set match_text [string range $json [lindex $match 0] [lindex $match 1]]
        if {[regexp {['"](.*?)['"]} $match_text -> vid]} {
            lappend videoIds $vid
        }
        set pos [expr {[lindex $match 1] + 1}]
    }
    
    # Extract all titles
    set titles {}
    set pos 0
    while {[regexp -start $pos -indices $title_pattern $json match] != 0} {
        set match_text [string range $json [lindex $match 0] [lindex $match 1]]
        if {[regexp {['"](.*?)['"]} $match_text -> title]} {
            set title [json_unescape_basic $title]
            lappend titles $title
        }
        set pos [expr {[lindex $match 1] + 1}]
    }
    
    putlog "\[yt-search PARSER\] Found [llength $videoIds] videoIDs and [llength $titles] titles"
    
    # Pair them up (should be roughly aligned due to YouTube API structure)
    set count [expr {[llength $videoIds] < [llength $titles] ? [llength $videoIds] : [llength $titles]}]
    for {set i 0} {$i < $count} {incr i} {
        set vid [lindex $videoIds $i]
        set title [lindex $titles $i]
        
        if {$vid ne "" && $title ne ""} {
            set url "https://www.youtube.com/watch?v=$vid"
            lappend results [dict create title $title url $url videoId $vid]
            putlog "\[yt-search PARSER\] Result $i: $title"
        }
    }
    
    return $results
}

proc youtube_search {query {max_results 5}} {
    global youtube_api_key
    
    if {![info exists youtube_api_key] || [string trim $youtube_api_key] eq ""} {
        error "youtube_api_key non definita in configurazione"
    }

    if {![string is integer -strict $max_results] || $max_results < 1 || $max_results > 50} {
        error "max_results deve essere un intero tra 1 e 50"
    }

    set api_key $youtube_api_key
    set encoded_query [url_encode $query]

    set url "https://www.googleapis.com/youtube/v3/search?part=snippet&type=video&maxResults=$max_results&q=$encoded_query&key=$api_key"

    putlog "\[yt-search DEBUG\] Query: $query | Encoded: $encoded_query | Max results: $max_results"
    
    set cmd [list curl -sS --connect-timeout 10 --max-time 30 $url]
    if {[catch {set response [exec {*}$cmd]} err]} {
        putlog "\[yt-search CURL ERROR\] $err"
        error "Errore curl: $err"
    }

    putlog "\[yt-search DEBUG\] Response length: [string length $response] bytes"
    
    if {[regexp {"error"\s*:\s*\{} $response]} {
        putlog "\[yt-search API ERROR\] $response"
        error "Errore API YouTube: $response"
    }

    set results [parse_search_results $response]
    putlog "\[yt-search DEBUG\] Found [llength $results] results"
    return $results
}

proc print_results {results} {
    if {[llength $results] == 0} {
        puts "Nessun risultato trovato."
        return
    }

    set i 1
    foreach item $results {
        puts "$i. [dict get $item title]"
        puts "   [dict get $item url]"
        incr i
    }
}

# IRC command handler for !yt
proc yt_search_cmd {nick host hand chan text} {
    global youtube_api_key
    
    set q [string trim $text]
    putlog "\[yt-search CMD\] User: $nick | Channel: $chan | Query: '$q'"
    
    if {$q eq ""} {
        puthelp "PRIVMSG $chan :$nick: Uso: !yt <ricerca>"
        return
    }
    
    if {[catch {set results [youtube_search $q 3]} err]} {
        putlog "\[yt-search ERROR\] $err"
        puthelp "PRIVMSG $chan :$nick: Errore: $err"
        return
    }
    
    if {[llength $results] == 0} {
        putlog "\[yt-search\] No results found for query: $q"
        puthelp "PRIVMSG $chan :$nick: Nessun risultato trovato per '$q'"
        return
    }
    
    set i 1
    foreach item $results {
        set title [dict get $item title]
        set url [dict get $item url]
        puthelp "PRIVMSG $chan :$nick: $i. $title"
        puthelp "PRIVMSG $chan :    $url"
        incr i
    }
}

# Safe bind registration
catch {unbind pub - "!yt" yt_search_cmd}
bind pub - "!yt" yt_search_cmd

putlog "✓ \[yt-search v$yt_search_version\] YouTube search module loaded successfully"

if {[info exists ::argv0] && [file tail [info script]] eq [file tail $::argv0]} {
    if {[llength $::argv] < 1} {
        puts "Uso: tclsh yt-search.tcl <query> ?max_results?"
        exit 1
    }

    set query [lindex $::argv 0]
    set max_results 5
    if {[llength $::argv] >= 2} {
        set max_results [lindex $::argv 1]
    }

    if {[catch {set results [youtube_search $query $max_results]} err]} {
        puts stderr "Errore: $err"
        exit 2
    }

    print_results $results
}
