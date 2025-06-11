#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <arpa/inet.h>
#include <time.h>
#include <signal.h>
#include <getopt.h>

#define IP "10.10.3.1"
#define PORT 22222
#define MAX 1024

volatile int running = 1;

void handle_signal(int signal) {
    running = 0;
}

int main(int argc, char *argv[]) {
    signal(SIGINT, handle_signal);

    int sockfd;
    struct sockaddr_in server_addr;
    char message[MAX + 1];
    int len;

    srand(time(NULL));

    if ((sockfd = socket(AF_INET, SOCK_DGRAM, 0)) < 0) {
        perror("socket");
        exit(EXIT_FAILURE);
    }

    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(PORT);
    if ((inet_pton(AF_INET, IP, &server_addr.sin_addr)) <= 0) {
        perror("inet_pton");
        close(sockfd);
        exit(EXIT_FAILURE);
    }

    int interval = 1;
    int count = 1;

    while (running) {
        len = (rand() % MAX) + 1;
        memset(message, 'A', len);
        message[len] = '\0';
        
        for (int i = 0; i < count; i++) {
            if ((sendto(sockfd, message, strlen(message), 0, (struct sockaddr*)&server_addr, sizeof(server_addr))) < 0) {
                perror("sendto");
                break;
            }
        }

        usleep(interval);
    }
    
    close(sockfd);
    return 0;
}

// compile:
// gcc -o udp_sender udp_sender.c
// execute:
// ./udp_sender