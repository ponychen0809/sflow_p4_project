#include <iostream>
#include <cstring>
#include <cstdlib>
#include <unistd.h>
#include <arpa/inet.h>

#define SERVER_IP "10.10.3.5"   // 修改成你要送去的 IP
#define SERVER_PORT 5001        // 修改成你要送去的 Port
#define PACKET_SIZE 512         // 每個封包 payload 大小（byte）

int main() {
    int sockfd;
    struct sockaddr_in server_addr;
    char buffer[PACKET_SIZE];

    // 建立 UDP socket
    sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (sockfd < 0) {
        perror("socket creation failed");
        exit(EXIT_FAILURE);
    }

    // 設定 server 位置
    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(SERVER_PORT);
    inet_pton(AF_INET, SERVER_IP, &server_addr.sin_addr);

    // 初始化封包內容（隨便填一些資料）
    memset(buffer, 'A', PACKET_SIZE);

    std::cout << "Press Enter to send a UDP packet of " << PACKET_SIZE << " bytes...\n";
    int a=0;
    while (true) {
        if(a%100==0)
            std::cin.get();  // 等待使用者按 Enter

        ssize_t sent_bytes = sendto(
            sockfd,
            buffer,
            PACKET_SIZE,
            0,
            (const struct sockaddr *)&server_addr,
            sizeof(server_addr)
        );

        if (sent_bytes < 0) {
            perror("sendto failed");
        } else {
            a++;
            std::cout <<"#"<<a <<" Sent " << sent_bytes << " bytes\n";
        }
    }

    close(sockfd);
    return 0;
}
