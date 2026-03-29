#!/usr/bin/env tclsh

# yt-search.tcl
# YouTube search utility for Tcl using YouTube Data API v3.

set yt_search_version "0.2.1"

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
    
    # Find items array first
    if {![string first "\"items\":" $json] >= 0} {
        putlog "\[yt-search PARSER\] No items array found in JSON"
        return $results
    }
    
    # Split by individual search results using a simple approach
    # Each result starts with "kind": "youtube#searchResult"
    set item_pattern {kind.*?youtube#searchResult}
    
    # Extract all blocks between each searchResult
    set pos [string first "\"items\":" $json]
    if {$pos < 0} {
        putlog "\[yt-search PARSER\] Could not find items array"
        return $results
    }
    
    # Get substring from items onwards
    set items_content [string range $json $pos end]
    
    # Count items and extract videoId and title pairs
    set count 0
    set search_pos 0
    
    while {1} {
        # Find next videoId
        set vid_pos [string first "\"videoId\":" $items_content $search_pos]
        if {$vid_pos < 0} {break}
        
        # Extract videoId value - find the quoted string after "videoId":
        set quote_start [string first "\"" $items_content [expr {$vid_pos + 11}]]
        if {$quote_start < 0} {break}
        
        set quote_end [string first "\"" $items_content [expr {$quote_start + 1}]]
        if {$quote_end < 0} {break}
        
        set videoId [string range $items_content [expr {$quote_start + 1}] [expr {$quote_end - 1}]]
        
        # Now find title after this videoId
        # Search for "title": in the next snippet block
        set title_search_start [expr {$quote_end + 1}]
        set snippet_start [string first "\"snippet\":" $items_content $title_search_start]
        
        if {$snippet_start < 0} {
            putlog "\[yt-search PARSER\] Could not find snippet after videoId at position $vid_pos"
            set search_pos [expr {$quote_end + 1}]
            continue
        }
        
        set title_pos [string first "\"title\":" $items_content $snippet_start]
        if {$title_pos < 0} {
            putlog "\[yt-search PARSER\] Could not find title in snippet"
            set search_pos [expr {$snippet_start + 1}]
            continue
        }
        
        # Extract title value
        set title_quote_start [string first "\"" $items_content [expr {$title_pos + 8}]]
        if {$title_quote_start < 0} {break}
        
        set title_quote_end [string first "\"" $items_content [expr {$title_quote_start + 1}]]
        if {$title_quote_end < 0} {break}
        
        set title [string range $items_content [expr {$title_quote_start + 1}] [expr {$title_quote_end - 1}]]
        set title [json_unescape_basic $title]
        
        # Add result if both videoId and title are found
        if {$videoId ne "" && $title ne ""} {
            set url "https://www.youtube.com/watch?v=$videoId"
            lappend results [dict create title $title url $url videoId $videoId]
            putlog "\[yt-search PARSER\] Result [incr count]: $title ($videoId)"
        }
        
        set search_pos [expr {$title_quote_end + 1}]
    }
    
    putlog "\[yt-search PARSER\] Extracted $count total results"
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
