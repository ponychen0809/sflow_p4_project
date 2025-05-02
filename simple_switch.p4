/* -*- P4_16 -*- */
#include <core.p4>
#include <tna.p4>

#include "common/headers.p4"
#include "common/util.p4"

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/
// @pragma stage 0 ipv4_table;
// @pragma stage 1 mac_table;
// /* 若要把 register 也獨立佔一個 stage，可再加 */
// @pragma stage 2 incr_total;

/* Ingress Parser */
enum bit<3> MIRROR_TYPE_t {
    I2E = 1,
    E2E = 2
}
const bit<32> SAMPLING_RATE = 256;
parser MyIngressParser(packet_in pkt,
                out my_header_t hdr,
                out my_metadata_t meta,
                out ingress_intrinsic_metadata_t ig_intr_md) {

    TofinoIngressParser() tofino_parser;
    state start {
        tofino_parser.apply(pkt, ig_intr_md);
        transition parse_ethernet;
    }

    state parse_ethernet {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            ETHERTYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        meta.pkt_len = (bit<32>)hdr.ipv4.total_len;
        meta.protocol   = (bit<32>)hdr.ipv4.protocol;
        meta.src_ip  = (bit<32>)hdr.ipv4.src_addr;
        meta.dst_ip  = (bit<32>)hdr.ipv4.dst_addr;
        meta.tos     = (bit<32>)hdr.ipv4.diffserv;
        transition select(hdr.ipv4.protocol) {
            IP_PROTOCOLS_TCP: parse_tcp;
            IP_PROTOCOLS_UDP: parse_udp;
            default: accept;
        }
    }

    state parse_tcp {
        pkt.extract(hdr.tcp);
        meta.src_port = (bit<32>)hdr.tcp.src_port;
        meta.dst_port = (bit<32>)hdr.tcp.dst_port;
        meta.tcp_flag = 0;

        transition accept;
    }

    state parse_udp {
        pkt.extract(hdr.udp);
        meta.src_port = (bit<32>)hdr.udp.src_port;
        meta.dst_port = (bit<32>)hdr.udp.dst_port;
        meta.tcp_flag = 0;
        transition accept;
    }
}


/* Ingress Pipeline */
control MyIngress(
                  /* User */
                  inout my_header_t hdr,
                  inout my_metadata_t meta,
                  /* Intrinsic */
                  in ingress_intrinsic_metadata_t ig_intr_md,
                  in ingress_intrinsic_metadata_from_parser_t ig_prsr_md,
                  inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md,
                  inout ingress_intrinsic_metadata_for_tm_t ig_tm_md) {

    action multicast() {
        ig_tm_md.mcast_grp_a = 1;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }

    action broadcast() {
        ig_tm_md.mcast_grp_a = 1;
    }

    action simple_forward(PortId_t port) {
        ig_tm_md.ucast_egress_port = port;
    }

    action send_back() {
        ig_tm_md.ucast_egress_port = ig_intr_md.ingress_port;
        hdr.ethernet.dst_addr = hdr.ethernet.src_addr;
        hdr.ipv4.dst_addr = hdr.ipv4.src_addr;
    }

    action ipv4_forward(PortId_t port) {
        ig_tm_md.ucast_egress_port = port;
    }
    table ipv4_table{
        
        key = {
            hdr.ipv4.dst_addr: exact;
        }
        actions = {
            ipv4_forward;
            multicast;
            send_back;
            simple_forward;
            NoAction;
        }
        size = 1024;
        default_action = NoAction;
    }
    table mac_table{
        key = {
            hdr.ethernet.dst_addr: exact;
        }
        actions = {
            broadcast;
            simple_forward;
            send_back;
            NoAction;
        }
        size = 1024;
        default_action = NoAction;
    }
    Register<bit<32>, bit<1>>(1) total_packets_reg;

    RegisterAction<bit<32>, bit<1>, bit<32>>(total_packets_reg)
        incr_total = {
            void apply(inout bit<32> v, out bit<32> new_val) {
                v       = v + 1;
                new_val = v;          // 把 +1 後的值回傳
            }
    };
    apply {
        ipv4_table.apply();
        // mac_table.apply();
        hdr.bridge.setValid();
        hdr.mirror.setValid();
        hdr.mirror.packet_type = 0;

        hdr.bridge.ingress_port = (bit<32>)ig_intr_md.ingress_port;
        hdr.bridge.egress_port  = (bit<32>) ig_tm_md.ucast_egress_port;
        hdr.udp.dst_port = (bit<16>)6345;
        hdr.bridge.pkt_len      = meta.pkt_len;
        hdr.bridge.protocol     = meta.protocol;
        hdr.bridge.src_ip       = meta.src_ip;
        hdr.bridge.dst_ip       = meta.dst_ip;
        hdr.bridge.src_port     = meta.src_port;
        hdr.bridge.dst_port     = meta.dst_port;
        hdr.bridge.tcp_flag     = meta.tcp_flag;
        hdr.bridge.tos          = meta.tos;

        hdr.sflow_hd.setValid();
        hdr.sflow_hd.version = (bit<32>)5;
        hdr.sflow_hd.address_type = (bit<32>)1;
        hdr.sflow_hd.agent_addr = (bit<32>)5;
        hdr.sflow_hd.sub_agent_id = (bit<32>)5;
        hdr.sflow_hd.sequence_number = (bit<32>)5;
        hdr.sflow_hd.uptime = (bit<32>)12345;
        hdr.sflow_hd.samples = (bit<32>)1;

        hdr.sflow_sample.setValid();
        hdr.sflow_sample.sample_type = (bit<32>)1;
        hdr.sflow_sample.sample_length = (bit<32>)80;
        hdr.sflow_sample.sample_seq_num = (bit<32>)1;
        hdr.sflow_sample.source_id = (bit<32>)1;
        hdr.sflow_sample.sampling_rate = (bit<32>)256;
        hdr.sflow_sample.sample_pool = (bit<32>)1;
        hdr.sflow_sample.drops = (bit<32>)0;
        hdr.sflow_sample.input_if = (bit<32>)hdr.bridge.ingress_port;
        hdr.sflow_sample.output_if = (bit<32>)hdr.bridge.egress_port;
        hdr.sflow_sample.record_count = (bit<32>)1;
        hdr.sflow_sample.enterprise_format = (bit<32>)1;
        hdr.sflow_sample.flow_length = (bit<32>)32;
        hdr.sflow_sample.pkt_length = (bit<32>)hdr.ipv4.total_len;
        hdr.sflow_sample.protocol = (bit<32>)hdr.ipv4.protocol;
        hdr.sflow_sample.src_ip = (bit<32>)hdr.ipv4.src_addr;
        hdr.sflow_sample.dst_ip = (bit<32>)hdr.ipv4.dst_addr;
        hdr.sflow_sample.src_port = (bit<32>)hdr.udp.src_port;
        hdr.sflow_sample.dst_port = (bit<32>)hdr.udp.dst_port;
        hdr.sflow_sample.tcp_flags = (bit<32>)0;
        hdr.sflow_sample.tos = (bit<32>)hdr.ipv4.diffserv;
        // hdr.bridge.pad0         = 0;
        if (hdr.ethernet.ether_type == ETHERTYPE_ARP) {
            multicast();
        }

        bit<32> cnt = incr_total.execute(0);  

        if (cnt % SAMPLING_RATE == 0) {
            ig_dprsr_md.mirror_type = MIRROR_TYPE_t.I2E;   // **I2E clone**
            meta.eg_mir_ses       = 27;                // session 27 由控制面設定
            
        }else{
            hdr.mirror.setValid();
            hdr.mirror.packet_type = 1;
        }
    }
}

/* Ingress Deparser*/

control MyIngressDeparser(packet_out pkt,
                            /* User */
                            inout my_header_t hdr,
                            in my_metadata_t meta,
                            /* Intrinsic */
                            in ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md) {

    /* Resource Definitions */
    Checksum() ipv4_checksum;
    Mirror() m;
    apply {
        if(hdr.ipv4.isValid()){
            hdr.ipv4.hdr_checksum = ipv4_checksum.update({
                hdr.ipv4.version,
                hdr.ipv4.ihl,
                hdr.ipv4.diffserv,
                hdr.ipv4.total_len,
                hdr.ipv4.identification,
                hdr.ipv4.flags,
                hdr.ipv4.frag_offset,
                hdr.ipv4.ttl,
                hdr.ipv4.protocol,
                hdr.ipv4.src_addr,
                hdr.ipv4.dst_addr
            });
        }


        if (ig_dprsr_md.mirror_type == MIRROR_TYPE_t.I2E) {
            m.emit<mirror_h>(meta.eg_mir_ses,{(bit<16>)0});
            hdr.mirror.setInvalid();
            // hdr.udp.dst_port = (bit<16>)6344;

        }
        pkt.emit(hdr.mirror);
        pkt.emit(hdr.bridge);
        pkt.emit(hdr.ethernet);
        pkt.emit(hdr.ipv4);
        pkt.emit(hdr.tcp);
        pkt.emit(hdr.udp);
        pkt.emit(hdr.sflow_hd);
        pkt.emit(hdr.sflow_sample);
    }
}

/* Egress pipeline */

parser MyEgressParser(
        packet_in pkt,
        out my_header_t hdr,
        out my_metadata_t eg_md,
        out egress_intrinsic_metadata_t eg_intr_md) {

    TofinoEgressParser() tofino_parser;
    
    state start {
        tofino_parser.apply(pkt, eg_intr_md);
        pkt.extract(hdr.mirror);             // mirror_h 一定在最前
        eg_md.packet_type = hdr.mirror.packet_type;
        transition parse_bridge;
    }

    state parse_bridge {
        pkt.extract(hdr.bridge);
        eg_md.ingress_port = hdr.bridge.ingress_port;
        transition parse_ethernet;
    }

    state parse_ethernet {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            ETHERTYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition accept;
    }
}

control MyEgress(
        inout my_header_t hdr,
        inout my_metadata_t eg_md,
        in egress_intrinsic_metadata_t eg_intr_md,
        in egress_intrinsic_metadata_from_parser_t eg_intr_md_from_prsr,
        inout egress_intrinsic_metadata_for_deparser_t eg_intr_dprs_md,
        inout egress_intrinsic_metadata_for_output_port_t eg_intr_oport_md) {

    action drop() {
        eg_intr_dprs_md.drop_ctl = 0b1;
    }

    // table reflect {
    //     key = {
    //         hdr.ipv4.src_addr: exact;
    //         eg_intr_md.egress_port: exact;
    //     }

    //     actions = {
    //         drop;
    //         NoAction;
    //     }

    //     default_action = NoAction;
    // }

    apply {
        // if (eg_md.packet_type == 1){
        //     drop();
        // }
        // eg_intr_dprs_md.truncate_len = 150;
        // if (eg_md.packet_type == 1){    //original packet
        //     hdr.udp.dst_port = (bit<16>)6344;
        //     // drop();
        // }else{   // cloned packet
        //     hdr.udp.dst_port = (bit<16>)6345;
        //     hdr.sflow_hd.setValid();
        //     hdr.sflow_hd.version = (bit<32>)5;
        //     hdr.sflow_hd.address_type = (bit<32>)1;
        //     hdr.sflow_hd.agent_addr = (bit<32>)5;
        //     hdr.sflow_hd.sub_agent_id = (bit<32>)5;
        //     hdr.sflow_hd.sequence_number = (bit<32>)5;
        //     hdr.sflow_hd.uptime = (bit<32>)12345;
        //     hdr.sflow_hd.samples = (bit<32>)1;

        //     hdr.sflow_sample.setValid();
        //     hdr.sflow_sample.sample_type = (bit<32>)1;
        //     hdr.sflow_sample.sample_length = (bit<32>)80;
        //     hdr.sflow_sample.sample_seq_num = (bit<32>)1;
        //     hdr.sflow_sample.source_id = (bit<32>)1;
        //     hdr.sflow_sample.sampling_rate = (bit<32>)256;
        //     hdr.sflow_sample.sample_pool = (bit<32>)1;
        //     hdr.sflow_sample.drops = (bit<32>)0;
        //     hdr.sflow_sample.input_if = (bit<32>)hdr.bridge.ingress_port;
        //     hdr.sflow_sample.output_if = (bit<32>)hdr.bridge.egress_port;
        //     hdr.sflow_sample.record_count = (bit<32>)1;
        //     hdr.sflow_sample.enterprise_format = (bit<32>)1;
        //     hdr.sflow_sample.flow_length = (bit<32>)32;
        //     hdr.sflow_sample.pkt_length = (bit<32>)hdr.bridge.pkt_len;
        //     hdr.sflow_sample.protocol = (bit<32>)hdr.bridge.protocol;
        //     hdr.sflow_sample.src_ip = (bit<32>)hdr.bridge.src_ip;
        //     hdr.sflow_sample.dst_ip = (bit<32>)hdr.bridge.dst_ip;
        //     hdr.sflow_sample.src_port = (bit<32>)hdr.bridge.src_port;
        //     hdr.sflow_sample.dst_port = (bit<32>)hdr.bridge.dst_port;
        //     hdr.sflow_sample.tcp_flags = (bit<32>)hdr.bridge.tcp_flag;
        //     hdr.sflow_sample.tos = (bit<32>)hdr.bridge.tos;


        //     // drop();
        // }
                
        // bit<32> in_port  = (bit<32>) eg_md.ingress_port;
        // bit<32> out_port = (bit<32>) eg_intr_md.egress_port;

        // if (in_port == out_port) {
        //     // drop();
        // }
    }
}

control MyEgressDeparser(
        packet_out pkt,
        inout my_header_t hdr,
        in my_metadata_t eg_md,
        in egress_intrinsic_metadata_for_deparser_t eg_intr_dprs_md) {

    apply {
        pkt.emit(hdr.ethernet);
        pkt.emit(hdr.ipv4);
        pkt.emit(hdr.tcp);
        pkt.emit(hdr.udp);

    }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

Pipeline(
    MyIngressParser(), MyIngress(), MyIngressDeparser(),
    MyEgressParser(), MyEgress(), MyEgressDeparser()
) pipe;

Switch(pipe) main;
