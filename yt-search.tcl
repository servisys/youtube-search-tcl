#!/usr/bin/env tclsh

# yt-search.tcl
# YouTube search utility for Tcl using YouTube Data API v3.

set yt_search_version "0.4.0"

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
    
    # Find the items array start
    set items_start [string first "\"items\":" $json]
    if {$items_start < 0} {
        putlog "\[yt-search PARSER\] ERROR: Could not find items array"
        return $results
    }
    
    set items_json [string range $json $items_start end]
    
    # Extract each result by looking for videoId patterns
    set pos 0
    set max_iterations 10
    set iteration 0
    
    while {$iteration < $max_iterations} {
        incr iteration
        
        # Find next videoId
        set vid_idx [string first "\"videoId\"" $items_json $pos]
        if {$vid_idx < 0} {
            break
        }
        
        # Find the quoted value after videoId
        set colon_idx [string first ":" $items_json $vid_idx]
        set quote_idx [string first "\"" $items_json $colon_idx]
        set quote_end_idx [string first "\"" $items_json [expr {$quote_idx + 1}]]
        
        if {$quote_idx < 0 || $quote_end_idx < 0} {
            set pos [expr {$vid_idx + 10}]
            continue
        }
        
        set videoId [string range $items_json [expr {$quote_idx + 1}] [expr {$quote_end_idx - 1}]]
        
        # Now find title in the following snippet section
        set snippet_idx [string first "\"snippet\"" $items_json $vid_idx]
        if {$snippet_idx < 0} {
            set pos [expr {$quote_end_idx + 1}]
            continue
        }
        
        set title_idx [string first "\"title\"" $items_json $snippet_idx]
        if {$title_idx < 0} {
            set pos [expr {$snippet_idx + 10}]
            continue
        }
        
        # Extract title value
        set title_colon_idx [string first ":" $items_json $title_idx]
        set title_quote_idx [string first "\"" $items_json $title_colon_idx]
        set title_quote_end_idx [string first "\"" $items_json [expr {$title_quote_idx + 1}]]
        
        if {$title_quote_idx < 0 || $title_quote_end_idx < 0} {
            set pos [expr {$title_idx + 8}]
            continue
        }
        
        set title [string range $items_json [expr {$title_quote_idx + 1}] [expr {$title_quote_end_idx - 1}]]
        set title [json_unescape_basic $title]
        
        # Add result
        if {[string length $videoId] > 0 && [string length $title] > 0} {
            set url "https://www.youtube.com/watch?v=$videoId"
            lappend results [dict create title $title url $url videoId $videoId]
            incr result_count
        }
        
        set pos [expr {$title_quote_end_idx + 1}]
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

    set results [parse_search_results $response]
    
    # Extract videoIds and get statistics
    set videoIds {}
    foreach result $results {
        lappend videoIds [dict get $result videoId]
    }
    
    set stats_map [get_video_stats $videoIds]
    
    # Enrich results with statistics
    set enriched_results {}
    foreach result $results {
        set vid [dict get $result videoId]
        if {[dict exists $stats_map $vid]} {
            dict set result views [dict get $stats_map $vid views]
            dict set result duration [dict get $stats_map $vid duration]
        } else {
            dict set result views "N/A"
            dict set result duration "N/A"
        }
        lappend enriched_results $result
    }
    
    return $enriched_results
}

proc get_video_stats {videoIds} {
    global youtube_api_key
    
    if {[llength $videoIds] == 0} {
        return {}
    }
    
    set api_key $youtube_api_key
    set ids_param [join $videoIds ","]
    
    # Call videos.list to get statistics and duration
    set url "https://www.googleapis.com/youtube/v3/videos?part=statistics,contentDetails&id=$ids_param&key=$api_key"
    
    set cmd [list curl -sS --connect-timeout 10 --max-time 30 $url]
    if {[catch {set response [exec {*}$cmd]} err]} {
        return {}
    }
    
    # Parse response to extract viewCount, likeCount, duration for each video
    set stats_map {}
    
    # Find items in response
    set pos 0
    while {1} {
        set id_idx [string first "\"id\":" $response $pos]
        if {$id_idx < 0} {break}
        
        # Extract video ID
        set quote_idx [string first "\"" $response [expr {$id_idx + 6}]]
        set quote_end [string first "\"" $response [expr {$quote_idx + 1}]]
        set video_id [string range $response [expr {$quote_idx + 1}] [expr {$quote_end - 1}]]
        
        # Extract statistics in the same block
        set stats_idx [string first "\"statistics\":" $response $id_idx]
        set next_item [string first "\"id\":" $response [expr {$id_idx + 10}]]
        if {$next_item < 0} {
            set next_item [string length $response]
        }
        set block [string range $response $stats_idx [expr {$next_item - 1}]]
        
        # Extract viewCount
        set view_idx [string first "\"viewCount\":" $block]
        set view_quote_idx [string first "\"" $block [expr {$view_idx + 13}]]
        set view_quote_end [string first "\"" $block [expr {$view_quote_idx + 1}]]
        set view_count [string range $block [expr {$view_quote_idx + 1}] [expr {$view_quote_end - 1}]]
        
        # Extract duration from contentDetails
        set duration_idx [string first "\"duration\":" $response $id_idx]
        if {$duration_idx > 0 && $duration_idx < [expr {$next_item}]} {
            set duration_quote_idx [string first "\"" $response [expr {$duration_idx + 12}]]
            set duration_quote_end [string first "\"" $response [expr {$duration_quote_idx + 1}]]
            set duration_iso [string range $response [expr {$duration_quote_idx + 1}] [expr {$duration_quote_end - 1}]]
            # Convert ISO 8601 to readable format: PT2M54S -> 2:54
            set duration [iso8601_to_readable $duration_iso]
        } else {
            set duration "?"
        }
        
        dict set stats_map $video_id "views" $view_count
        dict set stats_map $video_id "duration" $duration
        
        set pos [expr {$next_item}]
    }
    
    return $stats_map
}

proc iso8601_to_readable {iso_duration} {
    # Convert PT2M54S or PT1H2M3S to 2:54 or 1:02:03
    # Remove PT prefix
    set duration [string range $iso_duration 2 end]
    
    set hours 0
    set minutes 0
    set seconds 0
    
    # Extract hours
    if {[regexp {(\d+)H} $duration -> h]} {
        set hours $h
        set duration [regsub {(\d+)H} $duration ""]
    }
    
    # Extract minutes
    if {[regexp {(\d+)M} $duration -> m]} {
        set minutes $m
        set duration [regsub {(\d+)M} $duration ""]
    }
    
    # Extract seconds
    if {[regexp {(\d+)S} $duration -> s]} {
        set seconds $s
    }
    
    if {$hours > 0} {
        return [format "%d:%02d:%02d" $hours $minutes $seconds]
    } else {
        return [format "%d:%02d" $minutes $seconds]
    }
}

# IRC command handler for !yt
proc yt_search_cmd {nick host hand chan text} {
    global youtube_api_key
    
    set q [string trim $text]
    
    if {$q eq ""} {
        puthelp "PRIVMSG $chan :$nick: Uso: !yt <ricerca>"
        return
    }
    
    if {[catch {set results [youtube_search $q 3]} err]} {
        puthelp "PRIVMSG $chan :$nick: Errore: $err"
        return
    }
    
    if {[llength $results] == 0} {
        puthelp "PRIVMSG $chan :$nick: Nessun risultato trovato per '$q'"
        return
    }
    
    set i 1
    foreach item $results {
        set title [dict get $item title]
        set views [dict get $item views]
        set duration [dict get $item duration]
        set url [dict get $item url]
        
        # Format viewCount with thousands separator
        if {$views ne "N/A"} {
            set views_formatted [format_number $views]
        } else {
            set views_formatted "N/A"
        }
        
        puthelp "PRIVMSG $chan :$nick: $i. $title | Visualizzazioni: $views_formatted | Durata: $duration"
        incr i
    }
}

proc format_number {num} {
    # Add thousands separator: 1000000 -> 1,000,000
    if {![string is integer -strict $num]} {
        return $num
    }
    
    set result ""
    set count 0
    for {set i [expr {[string length $num] - 1}]} {$i >= 0} {incr i -1} {
        if {$count > 0 && $count % 3 == 0} {
            set result ",[string index $num $i]$result"
        } else {
            set result "[string index $num $i]$result"
        }
        incr count
    }
    return $result
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
