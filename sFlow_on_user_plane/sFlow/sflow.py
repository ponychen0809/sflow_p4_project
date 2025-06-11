from scapy.all import *

import struct
import time
import socket

ETHERNET_HEADER_LENGTH = 14
IP_HEADER_LENGTH = 20
UDP_HEADER_LENGTH = 8
SFLOW_HEADER_LENGTH = 28
SAMPLE_LENGTH = 80
MTU = 1500

class sFlowAgent:
    def __init__(self, datagram_version, address_type, agent_address, sub_agent_id, collector_address):
        self.datagram_version = datagram_version
        self.address_type = address_type
        self.agent_address = agent_address
        self.sub_agent_id = sub_agent_id
        self.datagram_sequence_number = 1
        self.start_time = time.time()
        self.sample_num = 0
        self.collector_address = collector_address
        self.port = 6343
        self.samples = b""
        self.enterprise = 0
        self.sample_type = 1
        self.sample_length = 72
        self.sample_sequence_number = 1
        source_id_type = 0
        source_id_index = 74
        self.source_id = (source_id_type << 24) | source_id_index
        self.sampling_rate = 256
        self.sample_pool = 0
        self.drops = 0
        self.record_num = 1
        self.format = 3
        self.flow_data_length = 32
        self.total_packets = 0

    def processSamples(self, ip_layer, layer4, ingress_port, egress_port):
        self.total_packets += self.sampling_rate
        uptime = int((time.time() - self.start_time) * 1000)
        with open("statistics.txt", "w") as file:
            file.write("{}\n".format(self.total_packets))
            file.write("{}\n".format(uptime))

        if (ETHERNET_HEADER_LENGTH + 
            IP_HEADER_LENGTH + 
            UDP_HEADER_LENGTH + 
            SFLOW_HEADER_LENGTH + 
            SAMPLE_LENGTH + 
            len(self.samples) > MTU):
            udp_datagram = (
                Ether(dst='ff:ff:ff:ff:ff:ff') / \
                IP(src=socket.gethostbyname("10.10.3.2"), dst=socket.gethostbyname(self.collector_address)) / \
                UDP(sport=self.port, dport=self.port) / \
                Raw(load=self.sFlowDatagram())
            )

            self.samples = b""
            self.addSample(ip_layer, layer4, ingress_port, egress_port)
            self.sample_num = 1

            return udp_datagram
        elif (ETHERNET_HEADER_LENGTH + 
              IP_HEADER_LENGTH + 
              UDP_HEADER_LENGTH + 
              SFLOW_HEADER_LENGTH + 
              SAMPLE_LENGTH + 
              len(self.samples) == MTU):
            self.addSample(ip_layer, layer4, ingress_port, egress_port)

            udp_datagram = (
                Ether(dst='ff:ff:ff:ff:ff:ff') / \
                IP(src=socket.gethostbyname("10.10.3.2"), dst=socket.gethostbyname(self.collector_address)) / \
                UDP(sport=self.port, dport=self.port) / \
                Raw(load=self.sFlowDatagram())
            )

            self.samples = b""
            self.sample_num = 0

            return udp_datagram
        else:
            self.addSample(ip_layer, layer4, ingress_port, egress_port)
            return None
        
    def addSample(self, ip_layer, layer4, ingress_port, egress_port):
        self.sample_pool += self.sampling_rate
        self.samples += (
            struct.pack('!I', self.sample_type) +
            struct.pack('!I', self.sample_length) + 
            struct.pack('!I', self.sample_sequence_number) +
            struct.pack('!I', self.source_id) +
            struct.pack('!I', self.sampling_rate) +
            struct.pack('!I', self.sample_pool) +
            struct.pack('!I', self.drops) +
            struct.pack('!I', ingress_port) +
            struct.pack('!I', egress_port) +
            struct.pack('!I', self.record_num) +

            # m records
            struct.pack('!I', ((self.enterprise << 12) | self.format)) +
            struct.pack('!I', self.flow_data_length) +
            struct.pack('!I', ip_layer.len) +
            struct.pack('!I', ip_layer.proto) +
            socket.inet_aton(ip_layer.src) +
            socket.inet_aton(ip_layer.dst) +
            struct.pack('!I', layer4.sport) +
            struct.pack('!I', layer4.dport) +
            struct.pack('!I', int(layer4.flags if ip_layer.proto == 6 else 0)) +
            struct.pack('!I', int(ip_layer.tos))
        )
        self.sample_num += 1
        self.sample_sequence_number += 1

    def sFlowDatagram(self):
        uptime = int((time.time() - self.start_time) * 1000)
        sflow_datagram = (
            struct.pack('!I', self.datagram_version) +
            struct.pack('!I', self.address_type) +
            socket.inet_aton(self.agent_address) +
            struct.pack('!I', self.sub_agent_id) +
            struct.pack('!I', self.datagram_sequence_number) +
            struct.pack('!I', uptime) +
            struct.pack('!I', self.sample_num) +
            # n samples
            self.samples
        )
        self.datagram_sequence_number += 1
        return sflow_datagram
