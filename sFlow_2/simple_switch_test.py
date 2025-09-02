####### PTF MODULE IMPORTS ########
import ptf
from ptf.testutils import *
from scapy.all import *
import queue as queue_module
####### PTF modules for BFRuntime Client Library APIs #######
import grpc
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
from bfruntime_client_base_tests import BfRuntimeTest

######## PTF modules for Fixed APIs (Thrift) ######
import pd_base_tests
from ptf.thriftutils import *
from res_pd_rpc import * # Common data types
from mc_pd_rpc import * # Multicast-specific data types
from mirror_pd_rpc import * # Mirror-specific data types

####### Additional imports ########
import pdb # To debug insert pdb.set_trace() anywhere

import const
import logging
import socket
import struct
import time
import sflow
import threading
import multiprocessing
MIRRORING_METADATA_OFFSET = 0
MIRRORING_METADATA_LENGTH = 8

ETHERNET_HEADER_OFFSET = MIRRORING_METADATA_OFFSET + MIRRORING_METADATA_LENGTH
ETHERNET_HEADER_LENGTH = 14

IP_HEADER_OFFSET = ETHERNET_HEADER_OFFSET + ETHERNET_HEADER_LENGTH
IP_HEADER_LENGTH = 20

TCP_HEADER_OFFSET = IP_HEADER_OFFSET + IP_HEADER_LENGTH
TCP_HEADER_LENGTH = 20

UDP_HEADER_OFFSET = IP_HEADER_OFFSET + IP_HEADER_LENGTH
UDP_HEADER_LENGTH = 20

TYPE_IPV4 = 0x0800
PROTO_TCP = 6
PROTO_UDP = 17

class Mirror(Packet):
    name = "Mirror"

    fields_desc = [
        ShortField("ingress_port", 0),
        ShortField("egress_port", 0),
        IntField("total_packets", 0)
    ]

logger = logging.getLogger('Test')
if not len(logger.handlers):
    logger.addHandler(logging.StreamHandler())

# Sample test case
class SimpleSwitchTest(BfRuntimeTest):
    def setUp(self):
        self.client_id = 0
        self.p4_name = test_param_get("simple_switch", "")
        self.dev = 0
        self.dev_tgt = gc.Target(self.dev, pipe_id=0xffff)

        # Connect to the program, running on the target
        BfRuntimeTest.setUp(self, self.client_id, self.p4_name)
        self.bfrt_info = self.interface.bfrt_info_get(self.p4_name)

        # self.mac_table = self.bfrt_info.table_get("MyIngress.mac_table")
        # self.mac_table.info.key_field_annotation_add("hdr.ethernet.dst_addr", "mac")

        self.ip_table = self.bfrt_info.table_get("MyIngress.ipv4_table")
        self.ip_table.info.key_field_annotation_add("hdr.ipv4.dst_addr", "ipv4")

        self.node_table = self.bfrt_info.table_get("$pre.node")
        self.mgid_table = self.bfrt_info.table_get("$pre.mgid")

        self.port_table = self.bfrt_info.table_get("$PORT")

        self.mirror_cfg_table = self.bfrt_info.table_get("$mirror.cfg")

        self.tables = [
            # self.mac_table,
            self.ip_table,
            self.node_table,
            self.mgid_table,
            self.port_table,
            self.mirror_cfg_table
        ]

        self.cleanUp()

    def runTest(self):
        # add mac table
        # self.mac_table.entry_add(
        #     self.dev_tgt,
        #     [self.mac_table.make_key([
        #         gc.KeyTuple('hdr.ethernet.dst_addr',
        #                     test_param_get("dst_addr", const.MacAddr.broadcast))]),
        #      self.mac_table.make_key([
        #         gc.KeyTuple('hdr.ethernet.dst_addr',
        #                     test_param_get("dst_addr", const.MacAddr.h1))]),
        #      self.mac_table.make_key([
        #         gc.KeyTuple('hdr.ethernet.dst_addr',
        #                     test_param_get("dst_addr", const.MacAddr.h3))]),
        #      self.mac_table.make_key([
        #         gc.KeyTuple('hdr.ethernet.dst_addr',
        #                     test_param_get("dst_addr", const.MacAddr.h2))])],
        #     [self.mac_table.make_data([], "MyIngress.broadcast"),
        #      self.mac_table.make_data([gc.DataTuple('port', const.port['h1'])], "MyIngress.simple_forward"),
        #      self.mac_table.make_data([gc.DataTuple('port', const.port['h3'])], "MyIngress.simple_forward"),
        #      self.mac_table.make_data([gc.DataTuple('port', const.port['h2'])], "MyIngress.simple_forward"),]
        # )

        # or add ip table
        self.ip_table.entry_add(
            self.dev_tgt,
            [
                self.ip_table.make_key([
                    gc.KeyTuple('hdr.ipv4.dst_addr',
                                test_param_get("dst_addr", const.IPAddr.h1))
                ]),
                self.ip_table.make_key([
                    gc.KeyTuple('hdr.ipv4.dst_addr',
                                test_param_get("dst_addr", const.IPAddr.h2))
                ]),
                self.ip_table.make_key([
                    gc.KeyTuple('hdr.ipv4.dst_addr',
                                test_param_get("dst_addr", const.IPAddr.h3))
                ]),
            ],
            [
                self.ip_table.make_data([gc.DataTuple('port', const.port['h1'])], "MyIngress.ipv4_forward"),
                self.ip_table.make_data([gc.DataTuple('port', const.port['h2'])], "MyIngress.ipv4_forward"),
                self.ip_table.make_data([gc.DataTuple('port', const.port['h3'])], "MyIngress.ipv4_forward"),
            ]
        )

        # add multicast node
        try:
            self.node_table.entry_add(
                self.dev_tgt,
                [self.node_table.make_key([
                    gc.KeyTuple('$MULTICAST_NODE_ID', 1)])],
                [self.node_table.make_data([
                    gc.DataTuple('$MULTICAST_RID', 1),
                    gc.DataTuple('$MULTICAST_LAG_ID', int_arr_val=[]),
                    gc.DataTuple('$DEV_PORT', int_arr_val=list(const.port.values()))])]
            )
        except Exception as e:
            print("Error on adding: {}".format(e))

        # add multicast node to table
        try:
            self.mgid_table.entry_add(
                self.dev_tgt,
                [self.mgid_table.make_key([
                    gc.KeyTuple('$MGID', 1)])],
                [self.mgid_table.make_data([
                    gc.DataTuple('$MULTICAST_NODE_ID', int_arr_val=[1]),
                    gc.DataTuple('$MULTICAST_NODE_L1_XID_VALID', bool_arr_val=[False]),
                    gc.DataTuple('$MULTICAST_NODE_L1_XID', int_arr_val=[0])])])
        except Exception as e:
            print("Error on adding: {}".format(e))

        # enable port for each host
        try:
            entry_key_h1 = self.port_table.make_key([
                gc.KeyTuple('$DEV_PORT', const.port['h1'])
            ])
            entry_key_h2 = self.port_table.make_key([
                gc.KeyTuple('$DEV_PORT', const.port['h2'])
            ])
            entry_key_h3 = self.port_table.make_key([
                gc.KeyTuple('$DEV_PORT', const.port['h3'])
            ])
            entry_data = self.port_table.make_data([
                gc.DataTuple("$SPEED", str_val="BF_SPEED_10G"),
                gc.DataTuple("$FEC", str_val="BF_FEC_TYP_NONE"),
                gc.DataTuple("$AUTO_NEGOTIATION", str_val="PM_AN_FORCE_DISABLE"),
                gc.DataTuple("$PORT_ENABLE", bool_val=True)
            ])
            self.port_table.entry_add(
                self.dev_tgt,
                [entry_key_h1, entry_key_h3, entry_key_h2],
                [entry_data, entry_data, entry_data]
            )
        except Exception as e:
            print("Error on adding: {}".format(e))

        # add a mirroring rule to table: session_id = 27 -> ucast_egress_port = 320
        try:
            self.mirror_cfg_table.entry_add(
                self.dev_tgt,
                [self.mirror_cfg_table.make_key([
                    gc.KeyTuple('$sid', 27)])],
                [self.mirror_cfg_table.make_data([
                    gc.DataTuple('$direction', str_val='EGRESS'),
                    gc.DataTuple('$session_enable', bool_val=True),
                    gc.DataTuple('$ucast_egress_port', 320),
                    gc.DataTuple('$ucast_egress_port_valid', bool_val=True),
                    gc.DataTuple('$max_pkt_len', 58)],
                    '$normal')]
            )
        except Exception as e:
            print("Error on adding: {}".format(e))

        self.handlePackets()
    
    def handlePackets(self):
        agent = sflow.sFlowAgent(
            datagram_version=5,
            address_type=1,
            agent_address="10.10.2.1",
            sub_agent_id=0,
            collector_address="10.10.3.1"
        )
        def handle_pkt(packet, agent, mirror, pkt_count,error_count,write_count,queue_max,queue):
            # print("\nwirte count", write_count.value)
            # print("===== handle packet ======")
            if len(packet) != 56:
                error_count.value += 1
                # print("error_count: ", error_count.value)
                return
            print("\n===============")
            print(os.getpid())
            print("queue max: ", queue_max.value)
            print("queue size: ", queue.qsize())
            print("wirte count", write_count.value)
            pkt_count.value += 1
            print("Receive packet: ", pkt_count.value)
            print("error_count: ", error_count.value)


            pkt = bytes(packet)
            mirror_pkt = Mirror(pkt[MIRRORING_METADATA_OFFSET:MIRRORING_METADATA_OFFSET + MIRRORING_METADATA_LENGTH])
            print("Total packet: ", mirror_pkt.total_packets)
            print("===============")
            ethernet = Ether(pkt[ETHERNET_HEADER_OFFSET:ETHERNET_HEADER_OFFSET + ETHERNET_HEADER_LENGTH])

            if ethernet.type != TYPE_IPV4:
                return

            ip = IP(pkt[IP_HEADER_OFFSET:IP_HEADER_OFFSET + IP_HEADER_LENGTH])

            if ip.proto != PROTO_TCP and ip.proto != PROTO_UDP:
                return

            if ip.proto == PROTO_TCP:
                tcp = TCP(pkt[TCP_HEADER_OFFSET:TCP_HEADER_OFFSET + TCP_HEADER_LENGTH])
                udp_datagram = agent.processSamples(ip_layer=ip, layer4=tcp, ingress_port=mirror_pkt.ingress_port,
                                                    egress_port=mirror_pkt.egress_port, total_packets=mirror_pkt.total_packets)
                if udp_datagram:
                    send_packet(self, 320, udp_datagram)   
            elif ip.proto == PROTO_UDP:
                udp = UDP(pkt[UDP_HEADER_OFFSET:UDP_HEADER_OFFSET + UDP_HEADER_LENGTH])
                udp_datagram = agent.processSamples(ip_layer=ip, layer4=udp, ingress_port=mirror_pkt.ingress_port,
                                                    egress_port=mirror_pkt.egress_port, total_packets=mirror_pkt.total_packets)
                if udp_datagram:
                    send_packet(self, 320, udp_datagram)   
        def write_queue(packet,queue,write_count,queue_max):
            try:
                queue.put(packet,block=False)
                # print("write ++++++++++++++")
                write_count.value +=1 
            except queue_module.Full:
                write_count.value = write_count.value
                # print("[ERROR] queue full !!!!!!!!!!!!!!!")
                # print("FULL!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
            
            
            

            # print("wirte count", write_count.value)
        def sniff_packets(queue,write_count,queue_max):
            # sniff(iface="enp6s0", prn=lambda x: queue.put(x,block=False), store=0)
            sniff(iface="enp6s0", prn=lambda packet: write_queue(packet, queue,write_count,queue_max), store=0)
            

        def handle_pkt_process(queue, agent, pkt_count,error_count,write_count,queue_max,handle_pkt_count,proc_id):
            # handle_pkt_count = 0
            log_file = "process_" + str(proc_id) + ".txt"
            f = open(log_file, "w")
            while True:
                f = open(log_file, "w")

                if not queue.empty():
                    if queue.qsize() > queue_max.value:
                        queue_max.value = queue.qsize()
                    # print("queue max: ",queue_max.value)
                    packet = queue.get()
                    handle_pkt_count.value += 1
                    f.write("handle_pkt_count: "+str(handle_pkt_count.value)+"\n")
                    print("handle_pkt_count: ", handle_pkt_count.value)
                    handle_pkt(packet, agent, None, pkt_count,error_count,write_count,queue_max,queue)  # 假設沒有實際的 mirror 參數
                f.close()

                # else:
                #     time.sleep(0.1)  # 避免過於頻繁的輪詢
        write_count = multiprocessing.Value('i', 0)
        error_count = multiprocessing.Value('i', 0)
        handle_pkt_count = multiprocessing.Value('i', 0)
 
        queue_max = multiprocessing.Value('i', 0)
        pkt_count = multiprocessing.Value('i', 0)
        packet_queue = multiprocessing.Queue(maxsize=80)
        sniff_process = multiprocessing.Process(target=sniff_packets, args=(packet_queue,write_count,queue_max))
        handle_process_1 = multiprocessing.Process(target=handle_pkt_process, args=(packet_queue, agent, pkt_count,error_count,write_count,queue_max,handle_pkt_count,1))
        handle_process_2 = multiprocessing.Process(target=handle_pkt_process, args=(packet_queue, agent, pkt_count,error_count,write_count,queue_max,handle_pkt_count,2))

        sniff_process.start()
        handle_process_1.start()
        handle_process_2.start()

        sniff_process.join()
        handle_process_1.join()
        handle_process_2.join()

    
    def cleanUp(self):
        try:
            for t in self.tables:
                t.entry_del(self.dev_tgt, [])
                try:
                    t.default_entry_reset(self.dev_tgt)
                except:
                    pass
        except Exception as e:
            print("Error cleaning up: {}".format(e))

    def tearDown(self):
        self.cleanUp()
        BfRuntimeTest.tearDown(self)
