#!/usr/bin/env tclsh

# yt-search.tcl
# YouTube search utility for Tcl using YouTube Data API v3.

set yt_search_version "0.2.2"

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
    set result_count 0
    
    # Debug: log first 800 chars of response to see structure
    putlog "\[yt-search PARSER\] JSON sample (first 800 chars):\n[string range $json 0 800]"
    
    # Very simple approach: split by items and extract videoId and title
    # Find the items array start
    set items_start [string first "\"items\":" $json]
    if {$items_start < 0} {
        putlog "\[yt-search PARSER\] ERROR: Could not find items array"
        return $results
    }
    
    set items_json [string range $json $items_start end]
    putlog "\[yt-search PARSER\] Items substring length: [string length $items_json]"
    
    # Extract each result by looking for videoId patterns
    set pos 0
    set max_iterations 10
    set iteration 0
    
    while {$iteration < $max_iterations} {
        incr iteration
        
        # Find next videoId
        set vid_idx [string first "\"videoId\"" $items_json $pos]
        if {$vid_idx < 0} {
            putlog "\[yt-search PARSER\] No more videoIds found after pos $pos"
            break
        }
        
        putlog "\[yt-search PARSER\] Found videoId at position $vid_idx"
        
        # Find the quoted value after videoId
        set colon_idx [string first ":" $items_json $vid_idx]
        set quote_idx [string first "\"" $items_json $colon_idx]
        set quote_end_idx [string first "\"" $items_json [expr {$quote_idx + 1}]]
        
        if {$quote_idx < 0 || $quote_end_idx < 0} {
            putlog "\[yt-search PARSER\] Could not extract videoId value"
            set pos [expr {$vid_idx + 10}]
            continue
        }
        
        set videoId [string range $items_json [expr {$quote_idx + 1}] [expr {$quote_end_idx - 1}]]
        putlog "\[yt-search PARSER\] Extracted videoId: '$videoId' (length: [string length $videoId])"
        
        # Now find title in the following snippet section
        set snippet_idx [string first "\"snippet\"" $items_json $vid_idx]
        if {$snippet_idx < 0} {
            putlog "\[yt-search PARSER\] Could not find snippet after videoId"
            set pos [expr {$quote_end_idx + 1}]
            continue
        }
        
        set title_idx [string first "\"title\"" $items_json $snippet_idx]
        if {$title_idx < 0} {
            putlog "\[yt-search PARSER\] Could not find title in snippet"
            set pos [expr {$snippet_idx + 10}]
            continue
        }
        
        # Extract title value
        set title_colon_idx [string first ":" $items_json $title_idx]
        set title_quote_idx [string first "\"" $items_json $title_colon_idx]
        set title_quote_end_idx [string first "\"" $items_json [expr {$title_quote_idx + 1}]]
        
        if {$title_quote_idx < 0 || $title_quote_end_idx < 0} {
            putlog "\[yt-search PARSER\] Could not extract title value"
            set pos [expr {$title_idx + 8}]
            continue
        }
        
        set title [string range $items_json [expr {$title_quote_idx + 1}] [expr {$title_quote_end_idx - 1}]]
        set title [json_unescape_basic $title]
        
        putlog "\[yt-search PARSER\] Extracted title: '$title' (length: [string length $title])"
        
        # Add result
        if {[string length $videoId] > 0 && [string length $title] > 0} {
            set url "https://www.youtube.com/watch?v=$videoId"
            lappend results [dict create title $title url $url videoId $videoId]
            incr result_count
            putlog "\[yt-search PARSER\] Result $result_count: $title"
        } else {
            putlog "\[yt-search PARSER\] Skipping empty result - videoId: '$videoId', title: '$title'"
        }
        
        set pos [expr {$title_quote_end_idx + 1}]
    }
    
    putlog "\[yt-search PARSER\] Total results extracted: $result_count"
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
