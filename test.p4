/* -*- P4_16 -*- */
#include <core.p4>
#include <tna.p4>


const bit<32> SAMPLING_RATE = 256;


/*===============================
=            PARSER             =
===============================*/
parser MyIngressParser(packet_in pkt,
                       out my_header_t hdr,
                       out my_metadata_t meta,
                       out ingress_intrinsic_metadata_t ig_intr_md)
{
    TofinoIngressParser() tofino_parser;
    state start {
        tofino_parser.apply(pkt, ig_intr_md);
        transition parse_eth;
    }

    state parse_eth {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            ETHERTYPE_IPV4: parse_ip;
            default:        accept;
        }
    }

    state parse_ip {
        pkt.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            IP_PROTOCOLS_TCP: parse_tcp;
            IP_PROTOCOLS_UDP: parse_udp;
            default:         accept;
        }
    }

    state parse_tcp {
        pkt.extract(hdr.tcp);
        transition accept;
    }

    state parse_udp {
        pkt.extract(hdr.udp);
        transition accept;
    }
}

/*===============================
=       INGRESS CONTROL         =
===============================*/
control MyIngress(inout my_header_t hdr,
                  inout my_metadata_t meta,
                  in ingress_intrinsic_metadata_t  ig_intr_md,
                  in ingress_intrinsic_metadata_from_parser_t ig_prsr_md,
                  inout ingress_intrinsic_metadata_for_deparser_t ig_dpr_md,
                  inout ingress_intrinsic_metadata_for_tm_t       ig_tm_md)
{
    /* ---------- Actions ---------- */
    action multicast()            { ig_tm_md.mcast_grp_a = 1; hdr.ipv4.ttl = hdr.ipv4.ttl - 1; }
    action broadcast()            { ig_tm_md.mcast_grp_a = 1; }
    action simple_forward(PortId_t p) { ig_tm_md.ucast_egress_port = p; }
    action send_back() {
        ig_tm_md.ucast_egress_port = ig_intr_md.ingress_port;
        hdr.ethernet.dst_addr = hdr.ethernet.src_addr;
        hdr.ipv4.dst_addr     = hdr.ipv4.src_addr;
    }
    action ipv4_forward(PortId_t p){ ig_tm_md.ucast_egress_port = p; hdr.ipv4.ttl = hdr.ipv4.ttl - 1; }

    /* ---------- Tables ---------- */
    table ipv4_table {
        key     = { hdr.ipv4.dst_addr: exact; }
        actions = { ipv4_forward; multicast; send_back; simple_forward; NoAction; }
        size    = 1024;
        default_action = NoAction;
    }

    table mac_table {
        key     = { hdr.ethernet.dst_addr: exact; }
        actions = { broadcast; simple_forward; send_back; NoAction; }
        size    = 1024;
        default_action = NoAction;
    }

    /* ---------- Packet Counter ---------- */
    Register<bit<32>, _>(1) total_packets;

    apply {
        /* 基本轉發 */
        ipv4_table.apply();
        mac_table.apply();

        /* 將 ingress_port 放進自訂 bridge header */
        hdr.bridge.setValid();
        hdr.bridge.ingress_port = ig_intr_md.ingress_port;
        hdr.bridge.pad0         = 0;

        /* ARP 直接廣播 */
        if (hdr.ethernet.ether_type == ETHERTYPE_ARP) {
            multicast();
        }

        /* ------ 取樣鏡像 (I2E) ------ */
        bit<32> cnt = total_packets.read(0) + 1;
        total_packets.write(0, cnt);

        if (cnt % SAMPLING_RATE == 0) {
            ig_dpr_md.mirror_type = MIRROR_TYPE_I2E;   // **I2E clone**
            meta.eg_mir_ses       = 27;                // session 27 由控制面設定
        }
    }
}

/*===============================
=      INGRESS DEPARSE          =
===============================*/
control MyIngressDeparser(packet_out pkt,
                          inout my_header_t hdr,
                          in  my_metadata_t  meta,
                          in  ingress_intrinsic_metadata_for_deparser_t ig_dpr_md)
{
    Checksum() ipv4_ck;

    apply {
        if (hdr.ipv4.isValid()) {
            hdr.ipv4.hdr_checksum = ipv4_ck.update({
                hdr.ipv4.version, hdr.ipv4.ihl, hdr.ipv4.diffserv,
                hdr.ipv4.total_len, hdr.ipv4.identification,
                hdr.ipv4.flags, hdr.ipv4.frag_offset,
                hdr.ipv4.ttl, hdr.ipv4.protocol,
                hdr.ipv4.src_addr, hdr.ipv4.dst_addr
            });
        }

        /* 若被標記為 I2E clone，插入 mirror_h */
        if (ig_dpr_md.mirror_type == MIRROR_TYPE_I2E) {
            Mirror() m;   // built-in extern
            m.emit<mirror_h>(meta.eg_mir_ses,
                             { 0, (bit<16>)hdr.bridge.ingress_port,
                                  (bit<16>)0 });
        }

        pkt.emit(hdr.bridge);
        pkt.emit(hdr.ethernet);
        pkt.emit(hdr.ipv4);
        pkt.emit(hdr.tcp);
        pkt.emit(hdr.udp);
    }
}

/*===============================
=       EGRESS PARSER           =
===============================*/
parser MyEgressParser(packet_in pkt,
                      out my_header_t hdr,
                      out my_metadata_t eg_md,
                      out egress_intrinsic_metadata_t eg_intr_md)
{
    TofinoEgressParser() tofino_parser;
    state start {
        tofino_parser.apply(pkt, eg_intr_md);             // 取 pkt_instance_type
        transition parse_bridge;
    }
    state parse_bridge {
        pkt.extract(hdr.bridge);
        eg_md.ingress_port = hdr.bridge.ingress_port;
        transition parse_eth;
    }
    state parse_eth {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            ETHERTYPE_IPV4: parse_ip;
            default:        accept;
        }
    }
    state parse_ip {
        pkt.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            IP_PROTOCOLS_TCP: parse_tcp;
            IP_PROTOCOLS_UDP: parse_udp;
            default:         accept;
        }
    }
    state parse_tcp { pkt.extract(hdr.tcp); transition accept; }
    state parse_udp { pkt.extract(hdr.udp); transition accept; }
}

/*===============================
=       EGRESS CONTROL          =
===============================*/
control MyEgress(inout my_header_t hdr,
                 inout my_metadata_t eg_md,
                 in egress_intrinsic_metadata_t  eg_intr_md,
                 in egress_intrinsic_metadata_from_parser_t eg_md_prs,
                 inout egress_intrinsic_metadata_for_deparser_t eg_dprs_md,
                 inout egress_intrinsic_metadata_for_output_port_t eg_oport_md)
{
    action normal_proc() {
        /* 原始封包的邏輯 (此處保留簡化) */
    }

    action clone_proc() {
        /* 對 clone 副本做專屬處理 — 這裡示範直接丟棄 */
        eg_dprs_md.drop_ctl = 0b1;
    }

    /* 防 self-loop 小 table */
    action drop() { eg_dprs_md.drop_ctl = 0b1; }
    table reflect {
        key = { hdr.ipv4.src_addr : exact;
                eg_intr_md.egress_port : exact; }
        actions = { drop; NoAction; }
        size = 1024;
        default_action = NoAction;
    }

    apply {
        reflect.apply();
        if (eg_md.ingress_port == eg_intr_md.egress_port) drop();

        /* ---- 分辨 NORMAL vs INGRESS_CLONE ---- */
        if (eg_intr_md.pkt_instance_type == PKT_INSTANCE_TYPE_INGRESS_CLONE) {
            clone_proc();
        } else {
            normal_proc();
        }

        eg_md.egress_port = eg_intr_md.egress_port;   // 給 deparser 用
    }
}

/*===============================
=      EGRESS DEPARSE           =
===============================*/
control MyEgressDeparser(packet_out pkt,
                         inout my_header_t hdr,
                         in my_metadata_t  eg_md,
                         in egress_intrinsic_metadata_for_deparser_t eg_dprs_md)
{
    apply {
        pkt.emit(hdr.ethernet);
        pkt.emit(hdr.ipv4);
        pkt.emit(hdr.tcp);
        pkt.emit(hdr.udp);
    }
}

/*===============================
=          PIPELINE             =
===============================*/
Pipeline(
    MyIngressParser(), MyIngress(), MyIngressDeparser(),
    MyEgressParser(),  MyEgress(),  MyEgressDeparser()
) pipe;
Switch(pipe) main;
