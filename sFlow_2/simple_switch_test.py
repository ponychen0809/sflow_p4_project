####### PTF MODULE IMPORTS ########
import ptf
from ptf.testutils import *
from scapy.all import *

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
pkt_count = 0
write_count = 0
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
    
    def _safe_parse_and_build(agent, raw_bytes):

        # 最小長度：Mirror(8) + Ether(14) + IPv4(min 20) + UDP(min 8) ≈ 50
        if len(raw_bytes) < 50:
            return None

        # 解析 Mirror metadata（8 bytes）
        mirror = Mirror(raw_bytes[0:8])

        # 用 Scapy 解析 L2+（避免手動算 header 長度、也支援 IP/TCP options）
        try:
            l2 = Ether(raw_bytes[8:])
        except Exception:
            return None

        if l2.type != 0x0800 or not l2.haslayer(IP):
            return None

        ip = l2[IP]

        # 只處理 TCP/UDP（其他協定略過）
        l4 = None
        if ip.proto == 6 and l2.haslayer(TCP):
            l4 = l2[TCP]
        elif ip.proto == 17 and l2.haslayer(UDP):
            l4 = l2[UDP]
        else:
            return None

        # 叫你的 sFlowAgent 組 datagram（可能不是每包都回傳）
        try:
            return agent.processSamples(
                ip_layer=ip,
                layer4=l4,
                ingress_port=mirror.ingress_port,
                egress_port=mirror.egress_port,
                total_packets=mirror.total_packets
            )
        except Exception:
            # 防護：解析/組包出錯就丟棄
            return None

    def handlePackets(self, iface="enp6s0", ptf_tx_port=320, timeout_sec=None):
    
        # 準備 sFlow agent
        agent = sflow.sFlowAgent(
            datagram_version=5,
            address_type=1,
            agent_address="10.10.2.1",
            sub_agent_id=0,
            collector_address="10.10.3.1"
        )

        q = Queue(maxsize=13312)        # FIFO
        stop_evt = threading.Event()

        # --- 1) sniff thread：只負責把封包轉成 bytes 丟進 FIFO ---
        def _producer():
            # 用局部回呼把 packet 轉 bytes；不要在這裡做重活
            def _enqueue(pkt):
                try:
                    
                    # 可加入基本過濾（例如最小長度），降低 worker 壓力
                    if len(pkt) == 56:
                        # print(11111)
                        global write_count
                        write_count = write_count +1
                        print("write_count: " ,write_count)
                        raw = bytes(pkt)
                        q.put_nowait(raw)
                        print("Queue size: " ,q.qsize())
                except Exception:
                    pass

            while not stop_evt.is_set():
                sniff(iface="enp6s0", prn=_enqueue)

        # --- 2) worker thread：從 FIFO 取封包，解析並送出 sFlow datagram ---
        def _consumer():
            print(threading.current_thread().name," === start...")
            while not stop_evt.is_set() or not q.empty():
                try:
                    raw = q.get(timeout=0.5)
                except Empty:
                    # print("Empty")
                    continue

                # datagram = _safe_parse_and_build(agent, raw)
                global pkt_count 
                pkt_count = pkt_count+1
                # print(threading.current_thread().name,", receive packet: ",pkt_count)
                mirror = Mirror(raw[MIRRORING_METADATA_OFFSET:MIRRORING_METADATA_OFFSET+MIRRORING_METADATA_LENGTH])
                # print(threading.current_thread().name,", total packet: ",mirror.total_packets)
                ethernet = Ether(raw[ETHERNET_HEADER_OFFSET:ETHERNET_HEADER_OFFSET+ETHERNET_HEADER_LENGTH])
                if (ethernet.type != TYPE_IPV4):
                    continue
                ip = IP(raw[IP_HEADER_OFFSET:IP_HEADER_OFFSET+IP_HEADER_LENGTH])
                
                if (ip.proto != PROTO_TCP and ip.proto != PROTO_UDP):
                    continue
                
                if (ip.proto == PROTO_TCP):
                    tcp = TCP(raw[TCP_HEADER_OFFSET:TCP_HEADER_OFFSET+TCP_HEADER_LENGTH])

                    udp_datagram = agent.processSamples(ip_layer=ip, layer4=tcp, ingress_port=mirror.ingress_port, egress_port=mirror.egress_port, total_packets=mirror.total_packets)
                    if udp_datagram:
                        send_packet(self, 320, udp_datagram)
                elif (ip.proto == PROTO_UDP):
                    udp = UDP(raw[UDP_HEADER_OFFSET:UDP_HEADER_OFFSET+UDP_HEADER_LENGTH])

                    udp_datagram = agent.processSamples(ip_layer=ip, layer4=udp, ingress_port=mirror.ingress_port, egress_port=mirror.egress_port, total_packets=mirror.total_packets)
                    if udp_datagram:
                        send_packet(self, 320, udp_datagram) 
               
                q.task_done()

        producer = threading.Thread(target=_producer, name="sniff-producer", daemon=True)
        consumer = threading.Thread(target=_consumer, name="sflow-consumer", daemon=True)
        consumer.start()
        producer.start()
        # consumers = []
        # for i in range(2):
        #                           # ★ 啟動多個 consumer
        #     t = threading.Thread(target=_consumer, name="consumer-{}".format(i), daemon=True)
        #     t.start()
        #     consumers.append(t)

        
        # 啟動
        # producer.start()
        

        # 若有 timeout，就等到時間到再收束；否則 Ctrl+C 可中斷
        try:
            if timeout_sec is not None:
                # 睡到 timeout；你也可以在這段期間做其他測試工作
                end = time.time() + timeout_sec
                while time.time() < end and producer.is_alive() and consumer.is_alive():
                    time.sleep(0.5)
            else:
                # 無限期運作到 KeyboardInterrupt
                while producer.is_alive() and consumer.is_alive():
                    time.sleep(0.5)
        except KeyboardInterrupt:
            pass
        finally:
            # 發出停止信號，並等隊列清空
            stop_evt.set()
            producer.join(timeout=2.0)
            # 等等隊列處理完（最多等 3 秒）
            q.join()
            consumer.join(timeout=2.0)
        # try:
        #     if timeout_sec is not None:
        #         end = time.time() + timeout_sec
        #         while time.time() < end and producer.is_alive() and all(t.is_alive() for t in consumers):
        #             time.sleep(0.5)
        #     else:
        #         while producer.is_alive() and all(t.is_alive() for t in consumers):
        #             time.sleep(0.5)
        # except KeyboardInterrupt:
        #     pass
        # finally:
        #     stop_evt.set()
        #     producer.join(timeout=2.0)
        #     q.join()
        #     for t in consumers:                                 # ★ 等所有 consumer 收尾
        #         t.join(timeout=2.0)
    
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
 