#!/usr/bin/env tclsh

# yt-search.tcl
# YouTube search utility for Tcl using YouTube Data API v3.

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

    # Extract each item block roughly between "id" and "snippet" occurrence.
    set blocks [regexp -all -inline {"videoId"\s*:\s*"[^"]+"[^\{\}]*"title"\s*:\s*"(?:[^"\\]|\\.)*"} $json]

    foreach block $blocks {
        set videoId ""
        set title ""

        if {[regexp {"videoId"\s*:\s*"([^"]+)"} $block -> videoId] && [regexp {"title"\s*:\s*"((?:[^"\\]|\\.)*)"} $block -> title]} {
            set title [json_unescape_basic $title]
            set url "https://www.youtube.com/watch?v=$videoId"
            lappend results [dict create title $title url $url videoId $videoId]
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

    set cmd [list curl -sS --connect-timeout 10 --max-time 30 $url]
    if {[catch {set response [exec {*}$cmd]} err]} {
        error "Errore curl: $err"
    }

    if {[regexp {"error"\s*:\s*\{} $response]} {
        error "Errore API YouTube: $response"
    }

    return [parse_search_results $response]
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

if {[file tail [info script]] eq [file tail $::argv0]} {
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
