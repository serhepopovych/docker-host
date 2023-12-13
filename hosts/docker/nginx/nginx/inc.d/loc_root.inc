
    #location @loc_root {
        # some requests come without Qualys-Scan header
        set $qualys_root 1;
        include /etc/nginx/inc.d/loc_qualys_scan.inc;

        allow 64.41.200.0/24;  # Qualys SSL Labs: SSL Server Test (free)
        deny all;

        # no noise in logs
        error_log /dev/null;
        access_log off;

        root @data_dir@/root;
        index index.html;
    #}
