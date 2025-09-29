#include <iostream>
#include <string>
#include <vector>
#include <chrono>
#include <thread>
#include <cstring>
#include <cstdlib>
#include <iomanip>      // for std::fixed, std::setprecision

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <net/if.h>

int main(int argc, char* argv[]) {
    if (argc != 8) {
        std::cerr << "Usage: " << argv[0]
                  << " <iface> <payload> <sleep_us> <dest_ip> <dest_port> <batch_size>\n";
        return 1;
    }

    const char* iface     = argv[1];            // e.g. "enp1s0"
    const char* payload   = argv[2];            // e.g. "HELLO"
    int         sleep_us  = std::stoi(argv[3]); // e.g. 10000 (10ms)
    const char* dest_ip   = argv[4];            // e.g. "10.10.3.2"
    int         dest_port = std::stoi(argv[5]); // e.g. 1234
    int         BATCH     = std::stoi(argv[6]); // e.g. 32
    int         duration     = std::stoi(argv[7]);

    size_t payload_len = std::strlen(payload);

    // 1) 建立 UDP socket
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) {
        perror("socket");
        return 1;
    }

    // 2) 如果想綁 interface（non-root 可能需要 CAP_NET_RAW，但 UDP 不一定）
    if (setsockopt(sock, SOL_SOCKET, SO_BINDTODEVICE,
                   iface, std::strlen(iface)) < 0) {
        perror("setsockopt(SO_BINDTODEVICE)");
        // 不成功也可繼續
    }

    // 3) 調大 send buffer
    int sndbuf = 16 * 1024 * 1024; // 16MB
    if (setsockopt(sock, SOL_SOCKET, SO_SNDBUF,
                   &sndbuf, sizeof(sndbuf)) < 0) {
        perror("setsockopt(SO_SNDBUF)");
    }

    // 4) 準備目的端 address
    struct sockaddr_in dst{};
    dst.sin_family = AF_INET;
    dst.sin_port   = htons(dest_port);
    if (inet_pton(AF_INET, dest_ip, &dst.sin_addr) != 1) {
        std::cerr << "Invalid dest IP\n";
        return 1;
    }

    // 5) 建立 batch 用的 mmsghdr & iovec 陣列
    std::vector<struct mmsghdr> msgs(BATCH);
    std::vector<struct iovec>  iovs(BATCH);
    for (int i = 0; i < BATCH; ++i) {
        std::memset(&msgs[i], 0, sizeof(msgs[i]));
        iovs[i].iov_base = const_cast<char*>(payload);
        iovs[i].iov_len  = payload_len;

        msgs[i].msg_hdr.msg_iov    = &iovs[i];
        msgs[i].msg_hdr.msg_iovlen = 1;
        msgs[i].msg_hdr.msg_name    = &dst;
        msgs[i].msg_hdr.msg_namelen = sizeof(dst);
    }

    // 6) 主迴圈：每 sleep_us 微秒送一次 batch
    uint64_t pkt_count   = 0;
    uint64_t total_bytes = 0;
    auto     t0 = std::chrono::steady_clock::now();

    while (true) {
        int sent = sendmmsg(sock, msgs.data(), BATCH, 0);
        if (sent < 0) {
            perror("sendmmsg");
            break;
        }
        pkt_count   += sent;
        // std::cout << payload_len << std::endl;
        total_bytes += uint64_t(sent) * (payload_len+28);
        // std::cout << total_bytes << std::endl;
        // std::cin.get();
        // 控速
        std::this_thread::sleep_for(
            std::chrono::microseconds(sleep_us)
        );
        
        // std::cout << "[SEND] " <<pkt_count << " packets.\n";
        // std::cin.get();
        // 15 秒後結束 & 印出平均速率
        auto tn = std::chrono::steady_clock::now();
        double elapsed = std::chrono::duration<double>(tn - t0).count();
        if (elapsed > duration) {
            double rate_bps  = total_bytes / elapsed;           // bytes/sec
            double rate_MBps = rate_bps / (1024.0 * 1024.0);    // MByte/sec

            std::cout << std::fixed << std::setprecision(2)
                      << "[Rate] AVG Sent "
                      << rate_MBps << " MByte/s ( " << rate_bps << " Byte/s)("
                      << rate_bps * 8 / 1e6 << " Mbit/s)\n";
            std::cout << "total byte: " << total_bytes << std::endl;
            std::cout << "Already sent " << pkt_count << " packets\n";
            break;
        }
    }

    close(sock);
    while(true){
        std::this_thread::sleep_for(
            std::chrono::microseconds(1000)
        );
    }
    return 0;
}
