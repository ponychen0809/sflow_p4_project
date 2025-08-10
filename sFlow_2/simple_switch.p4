/* -*- P4_16 -*- */
#include <core.p4>
#include <tna.p4>

#include "common/headers.p4"
#include "common/util.p4"

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

/* Ingress Parser */

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
        transition select(hdr.ipv4.protocol) {
            IP_PROTOCOLS_TCP: parse_tcp;
            IP_PROTOCOLS_UDP: parse_udp;
            default: accept;
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
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }

    table ipv4_table {
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

    table mac_table {
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

    apply {
        ipv4_table.apply();
        mac_table.apply();
        hdr.bridge.setValid();
        hdr.bridge.ingress_port = ig_intr_md.ingress_port;
        hdr.bridge.pad0 = 0;
        if (hdr.ethernet.ether_type == ETHERTYPE_ARP) {
            multicast();
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
        pkt.emit(hdr.bridge);
        pkt.emit(hdr.ethernet);
        pkt.emit(hdr.ipv4);
        pkt.emit(hdr.tcp);
        pkt.emit(hdr.udp);
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
        transition select(hdr.ipv4.protocol) {
            IP_PROTOCOLS_TCP: parse_tcp;
            IP_PROTOCOLS_UDP: parse_udp;
            default: accept;
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

control MyEgress(
        inout my_header_t hdr,
        inout my_metadata_t eg_md,
        in egress_intrinsic_metadata_t eg_intr_md,
        in egress_intrinsic_metadata_from_parser_t eg_intr_md_from_prsr,
        inout egress_intrinsic_metadata_for_deparser_t eg_intr_dprs_md,
        inout egress_intrinsic_metadata_for_output_port_t eg_intr_oport_md) {

    Register<bit<32>, _>(1) total_packets;
    
    action drop() {
        eg_intr_dprs_md.drop_ctl = 0b1;
    }

    table reflect {
        key = {
            hdr.ipv4.src_addr: exact;
            eg_intr_md.egress_port: exact;
        }

        actions = {
            drop;
            NoAction;
        }
        
        default_action = NoAction;
    }

    apply {
        // When a packet is forwarded, total_packets is incremented by 1.
        bit<32> total_packets_ = total_packets.read(0);
        total_packets.write(0, total_packets_ + 1);
        total_packets_ = total_packets_ + 1;

        // Every 256 packets forwarded, mark the packet to be mirrored.
        if (total_packets_ % 1024 == 0) {
            eg_intr_dprs_md.mirror_type = MIRROR_TYPE_E2E;
            eg_md.pkt_type = PKT_TYPE_MIRROR;
            eg_md.eg_mir_ses = 27;
            eg_md.total_packets = total_packets_;
        }

        reflect.apply();
        if (eg_md.ingress_port == eg_intr_md.egress_port) {
            drop();
        }
        eg_md.egress_port = eg_intr_md.egress_port;
    }
}

control MyEgressDeparser(
        packet_out pkt,
        inout my_header_t hdr,
        in my_metadata_t eg_md,
        in egress_intrinsic_metadata_for_deparser_t eg_intr_dprs_md) {
    
    Mirror() mirror;

    apply {
        // If the packet is marked to be mirrored, add a self-defined header.
        if (eg_intr_dprs_md.mirror_type == MIRROR_TYPE_E2E) {
            mirror.emit<mirror_h>(eg_md.eg_mir_ses, {
                0,
                (bit<16>)eg_md.ingress_port,
                (bit<16>)eg_md.egress_port,
                eg_md.total_packets
            });
        }

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
