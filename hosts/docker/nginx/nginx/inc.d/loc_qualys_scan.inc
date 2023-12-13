
    #location @loc_qualys_scan {
        # Permit scanner access to detect vulnerabilities
        allow 64.39.96.0/20;   # Qualys PCI scan (paid)
        allow 139.87.112.0/23;

        # scanner only
        if ($qualys_root) {
            set $no_qualys_scan 0;
        }
        if ($http_qualys_scan) {
            set $no_qualys_scan 0;
        }
        if ($no_qualys_scan) {
            return 403;
        }
    #}
