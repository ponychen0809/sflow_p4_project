#include <core.p4>
#include <tna.p4>



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

struct user_metadata_t {
    bit<32> ingress_port;
    bit<32> egress_port;
    bit<32> pkt_length;
    bit<32> protocol;
    bit<32> src_ip;
    bit<32> dst_ip;
    bit<32> src_port;
    bit<32> dst_port;
}

parser MyParser(
    packet_in pkt,
    out parsed_headers_t hdr,
    inout user_metadata_t user_md,
    inout ingress_intrinsic_metadata_t ig_intr_md
) {
    state start {
        user_md.ingress_port  = (bit<32>)ig_intr_md.ingress_port;
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

control MyIngress(
    inout parsed_headers_t hdr,
    inout user_metadata_t user_md,
    in ingress_intrinsic_metadata_t ig_intr_md,
    inout ingress_intrinsic_metadata_for_deparser_t ig_dpr_md,
    inout ingress_intrinsic_metadata_for_tm_t ig_tm_md
) {
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
            register_val = register_val+1;
        }
    };

    // ==================== register 0 ====================
    Register<bit<32>,bit<1>>(1) reg_ingress_port_0;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_0) reg_ingress_port_0_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.ingress_port;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_egress_port_0;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_0) reg_egress_port_0_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.egress_port;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_pkt_length_0;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_0) reg_pkt_length_0_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.pkt_length;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_protocol_0;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_0) reg_protocol_0_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.protocol;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_src_ip_0;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_0) reg_src_ip_0_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.src_ip;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_dst_ip_0;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_0) reg_dst_ip_0_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.dst_ip;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_src_port_0;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_0) reg_src_port_0_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.src_port;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_dst_port_0;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_0) reg_dst_port_0_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.dst_port;
        }
    };

    // ==================== register 1 ====================
    Register<bit<32>,bit<1>>(1) reg_ingress_port_1;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_1) reg_ingress_port_1_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.ingress_port;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_egress_port_1;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_1) reg_egress_port_1_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.egress_port;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_pkt_length_1;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_1) reg_pkt_length_1_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.pkt_length;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_protocol_1;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_1) reg_protocol_1_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.protocol;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_src_ip_1;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_1) reg_src_ip_1_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.src_ip;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_dst_ip_1;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_1) reg_dst_ip_1_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.dst_ip;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_src_port_1;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_1) reg_src_port_1_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.src_port;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_dst_port_1;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_1) reg_dst_port_1_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.dst_port;
        }
    };

    // ==================== register 2 ====================
    Register<bit<32>,bit<1>>(1) reg_ingress_port_2;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_2) reg_ingress_port_2_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.ingress_port;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_egress_port_2;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_2) reg_egress_port_2_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.egress_port;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_pkt_length_2;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_2) reg_pkt_length_2_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.pkt_length;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_protocol_2;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_2) reg_protocol_2_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.protocol;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_src_ip_2;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_2) reg_src_ip_2_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.src_ip;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_dst_ip_2;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_2) reg_dst_ip_2_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.dst_ip;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_src_port_2;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_2) reg_src_port_2_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.src_port;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_dst_port_2;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_2) reg_dst_port_2_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.dst_port;
        }
    };

    // ==================== register 3 ====================
    Register<bit<32>,bit<1>>(1) reg_ingress_port_3;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_3) reg_ingress_port_3_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.ingress_port;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_egress_port_3;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_3) reg_egress_port_3_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.egress_port;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_pkt_length_3;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_3) reg_pkt_length_3_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.pkt_length;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_protocol_3;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_3) reg_protocol_3_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.protocol;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_src_ip_3;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_3) reg_src_ip_3_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.src_ip;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_dst_ip_3;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_3) reg_dst_ip_3_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.dst_ip;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_src_port_3;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_3) reg_src_port_3_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.src_port;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_dst_port_3;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_3) reg_dst_port_3_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.dst_port;
        }
    };

    // ==================== register 4 ====================
    Register<bit<32>,bit<1>>(1) reg_ingress_port_4;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_4) reg_ingress_port_4_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.ingress_port;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_egress_port_4;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_4) reg_egress_port_4_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.egress_port;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_pkt_length_4;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_4) reg_pkt_length_4_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.pkt_length;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_protocol_4;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_4) reg_protocol_4_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.protocol;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_src_ip_4;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_4) reg_src_ip_4_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.src_ip;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_dst_ip_4;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_4) reg_dst_ip_4_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.dst_ip;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_src_port_4;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_4) reg_src_port_4_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.src_port;
        }
    };
    Register<bit<32>,bit<1>>(1) reg_dst_port_4;
    RegisterAction<bit<32>, bit<1>, bit<32>>(reg_ingress_port_4) reg_dst_port_4_action_read_set = {
        void apply(inout bit<32> register_val, out bit<32> read_val) {
            read_val = register_val;
            register_val = (bit<32>)user_md.dst_port;
        }
    };
    apply {
        ig_tm_md.ucast_egress_port = 2;
        // user_md.ingress_port = (bit<32>)ig_intr_md.ingress_port;
        // user_md.egress_port = (bit<32>)ig_dpr_md.egress_spec;
        // user_md.pkt_length = (bit<32>)ig_intr_md.packet_len;
        // user_md.protocol = (bit<32>)hdr.ip.protocol;
        // user_md.src_ip = (bit<32>)hdr.ip.src_addr;
        // user_md.dst_ip = (bit<32>)hdr.ip.dst_addr;
        // user_md.src_port = (bit<32>)hdr.udp.src_port;
        // user_md.dst_port = (bit<32>)hdr.udp.dst_port;

        bit<32> tmp_packet_count;
        tmp_packet_count = reg_packet_count_action_read_count.execute(0);
        if(tmp_packet_count == 0){
            reg_ingress_port_0_action_read_set.execute(0);
            reg_egress_port_0_action_read_set.execute(0);
            reg_pkt_length_0_action_read_set.execute(0);
            reg_protocol_0_action_read_set.execute(0);
            reg_src_ip_0_action_read_set.execute(0);
            reg_dst_ip_0_action_read_set.execute(0);
            reg_src_port_0_action_read_set.execute(0);
            reg_dst_port_0_action_read_set.execute(0);
        }else if(tmp_packet_count == 1){
            reg_ingress_port_1_action_read_set.execute(0);
            reg_egress_port_1_action_read_set.execute(0);
            reg_pkt_length_1_action_read_set.execute(0);
            reg_protocol_1_action_read_set.execute(0);
            reg_src_ip_1_action_read_set.execute(0);
            reg_dst_ip_1_action_read_set.execute(0);
            reg_src_port_1_action_read_set.execute(0);
            reg_dst_port_1_action_read_set.execute(0);
        }else if(tmp_packet_count == 2){
            reg_ingress_port_2_action_read_set.execute(0);
            reg_egress_port_2_action_read_set.execute(0);
            reg_pkt_length_2_action_read_set.execute(0);
            reg_protocol_2_action_read_set.execute(0);
            reg_src_ip_2_action_read_set.execute(0);
            reg_dst_ip_2_action_read_set.execute(0);
            reg_src_port_2_action_read_set.execute(0);
            reg_dst_port_2_action_read_set.execute(0);
        }else if(tmp_packet_count == 3){
            reg_ingress_port_3_action_read_set.execute(0);
            reg_egress_port_3_action_read_set.execute(0);
            reg_pkt_length_3_action_read_set.execute(0);
            reg_protocol_3_action_read_set.execute(0);
            reg_src_ip_3_action_read_set.execute(0);
            reg_dst_ip_3_action_read_set.execute(0);
            reg_src_port_3_action_read_set.execute(0);
            reg_dst_port_3_action_read_set.execute(0);
        }else if(tmp_packet_count == 4){
            reg_ingress_port_4_action_read_set.execute(0);
            reg_egress_port_4_action_read_set.execute(0);
            reg_pkt_length_4_action_read_set.execute(0);
            reg_protocol_4_action_read_set.execute(0);
            reg_src_ip_4_action_read_set.execute(0);
            reg_dst_ip_4_action_read_set.execute(0);
            reg_src_port_4_action_read_set.execute(0);
            reg_dst_port_4_action_read_set.execute(0);
        }
        ig_dpr_md.mirror_type = MIRROR_TYPE_t.I2E;
    }
}

control MyEgress(
    inout parsed_headers_t hdr,
    inout user_metadata_t user_md,
    in egress_intrinsic_metadata_from_parser_t eg_md,
    inout egress_intrinsic_metadata_t eg_intr_md
) {
    apply {
        if (hdr.ip.isValid()) {
            event_trace("Egress stage received IPv4 packet");
        }

    }
}

control MyDeparser(packet_out pkt, in parsed_headers_t hdr) {
    apply {
        pkt.emit(hdr.eth);
        pkt.emit(hdr.ip);
        pkt.emit(hdr.udp);
    }
}

control MyComputeChecksum(
    inout parsed_headers_t hdr,
    inout user_metadata_t user_md
) {
    apply {}
}

control MyVerifyChecksum(
    inout parsed_headers_t hdr,
    inout user_metadata_t user_md
) {
    apply {}
}

// TNAControl main = TNAControl(
//     MyParser(),
//     MyVerifyChecksum(),
//     MyIngress(),
//     MyEgress(),
//     MyComputeChecksum(),
//     MyDeparser()
// );
