
    #location @loc_non_root {
        set $qualys_root 0;
        include /etc/nginx/inc.d/loc_qualys_scan.inc;
    #}
