/* -*- P4_16 -*- */
#include <core.p4>
#include <tna.p4>

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/
const bit<16> ETHERNET_TYPE_IPV4 = 0x0800;
const bit<8> IP_PROTOCOL_UDP = 17;
#define SFLOW_DST_IP       0x7f000001  // 127.0.0.1
#define SFLOW_DST_PORT     6343
#define SFLOW_SRC_PORT     6343
#define SFLOW_VERSION      5

const bit<32> PKT_INSTANCE_TYPE_NORMAL        = 0;
const bit<32> PKT_INSTANCE_TYPE_INGRESS_CLONE = 1;
const bit<32> PKT_INSTANCE_TYPE_EGRESS_CLONE  = 2;
const bit<32> PKT_INSTANCE_TYPE_RECIRCULATE   = 3;
const bit<32> PKT_INSTANCE_TYPE_REPLICATION   = 4;

extern void event_trace(string s);

enum bit<3> MIRROR_TYPE_t {
    I2E = 1,
    E2E = 2
}

enum bit<8> PKT_TYPE_t {
    NORMAL = 0,
    TO_CPU = 1
}
enum bit<16> ETHER_TYPE_t {
    IPV4 = 0x0800,
    ARP = 0x0806,
    TPID = 0x8100,
    IPV6 = 0x86DD,
    MPLS = 0x8847,
    TO_CPU = 0xBF01,
    EVICT = 0xBF02
}
header ethernet_t {
    bit<48> dst_addr;
    bit<48> src_addr;
    bit<16> eth_type;
}

header ipv4_t {
    bit<4> version;
    bit<4> ihl;
    bit<8> tos;
    bit<16> total_length;
    bit<16> identification;
    bit<3> flags;
    bit<13> frag_offset;
    bit<8> ttl;
    bit<8> protocol;
    bit<16> hdr_checksum;
    bit<32> src_addr;
    bit<32> dst_addr;
}

header udp_t {
    bit<16> src_port;
    bit<16> dst_port;
    bit<16> length_;
    bit<16> checksum;
}
header sflow_t {
    bit<32> version;
    bit<32> address_type;
    bit<32> agent_addr;
    bit<32> sub_agent_id;
    bit<32> sequence_number;
    bit<32> uptime;
    bit<32> samples;
}

header sflow_sample_t {
    bit<32> sample_type;
    bit<32> sample_length;
    bit<32> sample_seq_num;
    bit<32> source_id;
    bit<32> sampling_rate;
    bit<32> sample_pool;
    bit<32> drops;
    bit<32> input_if;
    bit<32> output_if;
    bit<32> record_count;
    bit<32> enterprise_format;
    bit<32> flow_length;
    bit<32> pkt_length;
    bit<32> protocol;
    bit<32> src_ip;
    bit<32> dst_ip;
    bit<32> src_port;
    bit<32> dst_port;
    bit<32> tcp_flags;
    bit<32> tos;
}

struct parsed_headers_t {
    ethernet_t eth;
    ipv4_t ip;
    udp_t udp;
    sflow_t sflow;
    sflow_sample_t sflow_sample_0;
    sflow_sample_t sflow_sample_1;
    sflow_sample_t sflow_sample_2;
    sflow_sample_t sflow_sample_3;
    sflow_sample_t sflow_sample_4;
    
}
header bridge_h {
    PKT_TYPE_t      pkt_type;
    // bit<32>         to_cpu_count;
}

struct user_metadata_t {
    bit<32> ingress_port;
    bit<32> egress_port;
    bit<32> pkt_length;
    bit<32> protocol;
    bit<32> src_ip;
    bit<32> dst_ip;
    bit<32> src_port;
    bit<32> dst_port;
    bit<1> is_clone;
    bridge_h bridge;
    MirrorId_t mirror_session;
}


/*===============================
=            Parsing            =
===============================*/
/* Ingress Parser */

// Parser for tofino-specific metadata.

// my ingress parser
parser MyIngressParser(packet_in pkt,
                out parsed_headers_t hdr,
                out user_metadata_t user_md,
                out ingress_intrinsic_metadata_t ig_intr_md) {

    state start {
        // user_md.ingress_port  = (bit<32>)ig_intr_md.ingress_port;
        pkt.extract(hdr.eth);
        transition select(hdr.eth.eth_type) {
            ETHERNET_TYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(hdr.ip);
        user_md.src_ip = (bit<32>)hdr.ip.src_addr;
        user_md.dst_ip = (bit<32>)hdr.ip.dst_addr;
        user_md.pkt_length = (bit<32>)hdr.ip.total_length;
        user_md.protocol = (bit<32>)hdr.ip.protocol;
        transition select(hdr.ip.protocol) {
            IP_PROTOCOL_UDP: parse_udp;
            default: accept;
        }
    }

    state parse_udp {
        pkt.extract(hdr.udp);
        user_md.src_port = (bit<32>)hdr.udp.src_port;
        user_md.dst_port = (bit<32>)hdr.udp.dst_port;
        transition accept;
    }

}


/* Ingress Pipeline */

control MyIngress(
                  /* User */
                  inout parsed_headers_t hdr,
                  inout user_metadata_t user_md,
                  /* Intrinsic */
                  in ingress_intrinsic_metadata_t ig_intr_md,
                  in ingress_intrinsic_metadata_from_parser_t ig_prsr_md,
                  inout ingress_intrinsic_metadata_for_deparser_t ig_dpr_md,
                  inout ingress_intrinsic_metadata_for_tm_t ig_tm_md) {

    Register<bit<32>,bit<1>>(1) reg_sample_count;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_sample_count) reg_sample_count_action_read_count = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = register_val+1;
        }
    };

    Register<bit<32>,bit<1>>(1) reg_packet_count;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_packet_count) reg_packet_count_action_read_count = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = register_val+1;
        }
    };
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_packet_count) reg_packet_count_action_reset = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = 0;
        }
    };

// ==================== register 0 ====================
    Register<bit<32>,bit<1>>(1, 0) reg_ingress_port_0;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_0) reg_ingress_port_0_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.ingress_port;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_egress_port_0;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_egress_port_0) reg_egress_port_0_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.egress_port;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_pkt_length_0;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_pkt_length_0) reg_pkt_length_0_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.pkt_length;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_protocol_0;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_protocol_0) reg_protocol_0_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.protocol;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_src_ip_0;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_src_ip_0) reg_src_ip_0_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.src_ip;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_dst_ip_0;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_dst_ip_0) reg_dst_ip_0_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.dst_ip;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_src_port_0;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_src_port_0) reg_src_port_0_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.src_port;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_dst_port_0;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_dst_port_0) reg_dst_port_0_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.dst_port;
        }
    };

// ==================== register 1 ====================
    Register<bit<32>,bit<1>>(1, 0) reg_ingress_port_1;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_1) reg_ingress_port_1_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.ingress_port;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_egress_port_1;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_egress_port_1) reg_egress_port_1_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.egress_port;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_pkt_length_1;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_pkt_length_1) reg_pkt_length_1_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.pkt_length;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_protocol_1;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_protocol_1) reg_protocol_1_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.protocol;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_src_ip_1;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_src_ip_1) reg_src_ip_1_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.src_ip;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_dst_ip_1;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_dst_ip_1) reg_dst_ip_1_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.dst_ip;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_src_port_1;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_src_port_1) reg_src_port_1_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.src_port;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_dst_port_1;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_dst_port_1) reg_dst_port_1_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.dst_port;
        }
    };

// ==================== register 2 ====================
    Register<bit<32>,bit<1>>(1, 0) reg_ingress_port_2;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_2) reg_ingress_port_2_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.ingress_port;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_egress_port_2;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_egress_port_2) reg_egress_port_2_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.egress_port;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_pkt_length_2;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_pkt_length_2) reg_pkt_length_2_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.pkt_length;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_protocol_2;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_protocol_2) reg_protocol_2_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.protocol;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_src_ip_2;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_src_ip_2) reg_src_ip_2_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.src_ip;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_dst_ip_2;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_dst_ip_2) reg_dst_ip_2_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.dst_ip;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_src_port_2;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_2) reg_src_port_2_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.src_port;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_dst_port_2;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_dst_port_2) reg_dst_port_2_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.dst_port;
        }
    };

// ==================== register 3 ====================
    Register<bit<32>,bit<1>>(1, 0) reg_ingress_port_3;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_3) reg_ingress_port_3_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.ingress_port;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_egress_port_3;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_egress_port_3) reg_egress_port_3_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.egress_port;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_pkt_length_3;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_pkt_length_3) reg_pkt_length_3_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.pkt_length;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_protocol_3;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_protocol_3) reg_protocol_3_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.protocol;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_src_ip_3;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_src_ip_3) reg_src_ip_3_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.src_ip;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_dst_ip_3;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_dst_ip_3) reg_dst_ip_3_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.dst_ip;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_src_port_3;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_src_port_3) reg_src_port_3_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.src_port;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_dst_port_3;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_dst_port_3) reg_dst_port_3_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.dst_port;
        }
    };
    //
// ==================== register 4 ====================
    Register<bit<32>,bit<1>>(1, 0) reg_ingress_port_4;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_4) reg_ingress_port_4_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.ingress_port;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_egress_port_4;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_egress_port_4) reg_egress_port_4_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.egress_port;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_pkt_length_4;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_pkt_length_4) reg_pkt_length_4_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.pkt_length;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_protocol_4;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_protocol_4) reg_protocol_4_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.protocol;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_src_ip_4;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_src_ip_4) reg_src_ip_4_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.src_ip;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_dst_ip_4;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_dst_ip_4) reg_dst_ip_4_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.dst_ip;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_src_port_4;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_src_port_4) reg_src_port_4_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.src_port;
        }
    };
    Register<bit<32>,bit<1>>(1, 0) reg_dst_port_4;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_dst_port_4) reg_dst_port_4_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.dst_port;
        }
    };
//
    apply {
        user_md.ingress_port  = (bit<32>)ig_intr_md.ingress_port;
        if (user_md.ingress_port == 144) {
            ig_tm_md.ucast_egress_port = 147;
            return;
        }
        ig_tm_md.ucast_egress_port = 147;
        // bit<32> tmp_packet_count;   
        // tmp_packet_count = reg_packet_count_action_read_count.execute(0);
        // if(tmp_packet_count == 0){
        //     reg_ingress_port_0_action_read_set.execute(0);
        //     reg_egress_port_0_action_read_set.execute(0);
        //     reg_pkt_length_0_action_read_set.execute(0);
        //     reg_protocol_0_action_read_set.execute(0);
        //     reg_src_ip_0_action_read_set.execute(0);
        //     reg_dst_ip_0_action_read_set.execute(0);
        //     reg_src_port_0_action_read_set.execute(0);
        //     reg_dst_port_0_action_read_set.execute(0);
        // }else if(tmp_packet_count == 1){
        //     reg_ingress_port_1_action_read_set.execute(0);
        //     reg_egress_port_1_action_read_set.execute(0);
        //     reg_pkt_length_1_action_read_set.execute(0);
        //     reg_protocol_1_action_read_set.execute(0);
        //     reg_src_ip_1_action_read_set.execute(0);
        //     reg_dst_ip_1_action_read_set.execute(0);
        //     reg_src_port_1_action_read_set.execute(0);
        //     reg_dst_port_1_action_read_set.execute(0);
        // }else if(tmp_packet_count == 2){
        //     reg_ingress_port_2_action_read_set.execute(0);
        //     reg_egress_port_2_action_read_set.execute(0);
        //     reg_pkt_length_2_action_read_set.execute(0);
        //     reg_protocol_2_action_read_set.execute(0);
        //     reg_src_ip_2_action_read_set.execute(0);
        //     reg_dst_ip_2_action_read_set.execute(0);
        //     reg_src_port_2_action_read_set.execute(0);
        //     reg_dst_port_2_action_read_set.execute(0);
        // }else if(tmp_packet_count == 3){
        //     reg_ingress_port_3_action_read_set.execute(0);
        //     reg_egress_port_3_action_read_set.execute(0);
        //     reg_pkt_length_3_action_read_set.execute(0);
        //     reg_protocol_3_action_read_set.execute(0);
        //     reg_src_ip_3_action_read_set.execute(0);
        //     reg_dst_ip_3_action_read_set.execute(0);
        //     reg_src_port_3_action_read_set.execute(0);
        //     reg_dst_port_3_action_read_set.execute(0);
        // }else if(tmp_packet_count >= 4){
        //     reg_ingress_port_4_action_read_set.execute(0);
        //     reg_egress_port_4_action_read_set.execute(0);
        //     reg_pkt_length_4_action_read_set.execute(0);
        //     reg_protocol_4_action_read_set.execute(0);
        //     reg_src_ip_4_action_read_set.execute(0);
        //     reg_dst_ip_4_action_read_set.execute(0);
        //     reg_src_port_4_action_read_set.execute(0);
        //     reg_dst_port_4_action_read_set.execute(0);

        //     // reg_packet_count_action_reset.execute(0); 
        // }
        ig_dpr_md.mirror_type = MIRROR_TYPE_t.I2E;
        user_md.mirror_session = 99;
    }
}

/* Ingress Deparser*/

control MyIngressDeparser(packet_out pkt,
                            /* User */
                            inout parsed_headers_t hdr,
                            in user_metadata_t user_md,
                            /* Intrinsic */
                            in ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md) {
                                
    // Checksum() ipv4_checksum;
    Mirror() mirror;
    
    apply {
        pkt.emit(hdr.eth);
        pkt.emit(hdr.ip);
        pkt.emit(hdr.udp);
        // bit<8> session_id;
        bit<1> cloned_flag;
        cloned_flag = 1;
        // PKT_TYPE_t pkt_type = PKT_TYPE_t.CLONED;
        if (ig_dprsr_md.mirror_type == MIRROR_TYPE_t.I2E) {
            mirror.emit<bridge_h>(user_md.mirror_session, {PKT_TYPE_t.NORMAL});
        }
    }
}

/* Egress pipeline */

parser MyEgressParser(
        packet_in pkt,
        out parsed_headers_t hdr,
        out user_metadata_t user_md,
        out egress_intrinsic_metadata_t eg_intr_md) {
    // Checksum() l4_checksum;

    state start {
        pkt.extract(eg_intr_md);
        transition parse_bridge;
    }

    state parse_bridge {
        pkt.extract(user_md.bridge);
        transition select(user_md.bridge.pkt_type) {
            PKT_TYPE_t.NORMAL : parse_ethernet;
            // PKT_TYPE_t.TO_CPU : parse_ethernet;
            default : accept;
        }
    }
    state parse_ethernet {
        pkt.extract(hdr.eth);
        transition select(hdr.eth.eth_type) {
            // ETHER_TYPE_t.TPID:  parse_vlan_tag;
            ETHER_TYPE_t.IPV4:  parse_ipv4;
            // ETHER_TYPE_t.TO_CPU:  parse_to_cpu;
            default: accept;
        }
    }
    state parse_ipv4 {
        pkt.extract(hdr.ip);
        // user_md.src_ip = (bit<32>)hdr.ip.src_addr;
        // user_md.dst_ip = (bit<32>)hdr.ip.dst_addr;
        // user_md.pkt_length = (bit<32>)hdr.ip.total_length;
        // user_md.protocol = (bit<32>)hdr.ip.protocol;
        // user_md.src_ip = (bit<32>)hdr.ip.src_addr;
        // user_md.dst_ip = (bit<32>)hdr.ip.dst_addr;
        // user_md.pkt_length = (bit<32>)hdr.ip.total_length;
        // user_md.protocol = (bit<32>)hdr.ip.protocol;
        transition select(hdr.ip.protocol) {
            IP_PROTOCOL_UDP: parse_udp;
            default: accept;
        }
    }

    state parse_udp {
        pkt.extract(hdr.udp);
        // user_md.src_port = (bit<32>)hdr.udp.src_port;
        // user_md.dst_port = (bit<32>)hdr.udp.dst_port;
        transition accept;
    }
}

control MyEgress(
        inout parsed_headers_t hdr,
        inout user_metadata_t user_md,
        in egress_intrinsic_metadata_t eg_intr_md,
        in egress_intrinsic_metadata_from_parser_t eg_intr_md_from_prsr,
        inout egress_intrinsic_metadata_for_deparser_t eg_intr_dprs_md,
        inout egress_intrinsic_metadata_for_output_port_t eg_intr_oport_md) {

    apply {
        if(user_md.bridge.pkt_type == PKT_TYPE_t.TO_CPU){
            hdr.eth.setValid();
            hdr.ip.setValid();
            hdr.udp.setValid();
            // hdr.sflow.setValid();
            // hdr.sflow_sample_0.setValid();
            // hdr.sflow_sample_1.setValid();
            // hdr.sflow_sample_2.setValid();
            // hdr.sflow_sample_3.setValid();
            // hdr.sflow_sample_4.setValid();
        }else{
            hdr.eth.setValid();
            hdr.ip.setValid();
            hdr.udp.setValid();
        }
        // if (eg_intr_md.pkt_instance_type == PKT_INSTANCE_TYPE_INGRESS_CLONE) {
        //     hdr.eth.setValid();
        //     hdr.ip.setValid();
        //     hdr.udp.setValid();
        //     hdr.sflow.setValid();
        //     hdr.sflow_sample_0.setValid();
        //     hdr.sflow_sample_1.setValid();
        //     hdr.sflow_sample_2.setValid();
        //     hdr.sflow_sample_3.setValid();
        //     hdr.sflow_sample_4.setValid();
        // }
    }
}

control MyEgressDeparser(
        packet_out pkt,
        inout parsed_headers_t hdr,
        in user_metadata_t user_md,
        in egress_intrinsic_metadata_for_deparser_t eg_intr_dprs_md) {
    Checksum() ipv4_checksum;
    apply {
        // if(hdr.ipv4.isValid()){
        //     hdr.ipv4.hdr_checksum = ipv4_checksum.update({
        //         /* 16-bit word  0   */ hdr.ipv4.version, hdr.ipv4.ihl, hdr.ipv4.diffserv,
        //         /* 16-bit word  1   */ hdr.ipv4.total_len,
        //         /* 16-bit word  2   */ hdr.ipv4.identification,
        //         /* 16-bit word  3   */ hdr.ipv4.flags, hdr.ipv4.frag_offset,
        //         /* 16-bit word  4   */ hdr.ipv4.ttl, hdr.ipv4.protocol,
        //         /* 16-bit word  5 skip hdr.ipv4.hdrChecksum, */
        //         /* 16-bit word  6-7 */ hdr.ipv4.src_addr,
        //         /* 16-bit word  8-9 */ hdr.ipv4.dst_addr
        //     });
        //     // l4_checksum.update({
        //     //     /* 16-bit words 0-1 */ hdr.ipv4.src_addr,
        //     //     /* 16-bit words 2-3 */ hdr.ipv4.dst_addr
        //     // });
        // }
        pkt.emit(hdr.eth);
        pkt.emit(hdr.ip);
        pkt.emit(hdr.udp);
        // pkt.emit(hdr.sflow);
        // pkt.emit(hdr.sflow_sample_0);
        // pkt.emit(hdr.sflow_sample_1);
        // pkt.emit(hdr.sflow_sample_2);
        // pkt.emit(hdr.sflow_sample_3);
        // pkt.emit(hdr.sflow_sample_4);
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
