import socket
import sys


def start_server(port):
    host = ''
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.bind((host, port))
    server_socket.listen()
    print(f"Server läuft auf {host}:{port}, warte auf Verbindungen...")
    while True:
        client_socket, client_address = server_socket.accept()
        print(f"Verbindung von {client_address} angenommen.")
        while True:
            data = client_socket.recv(1024).decode('utf-8', errors="ignore")
            print(f"Empfangene Daten: {data}")
            if not data:
                break
        client_socket.close()

# Start des Servers
if __name__ == "__main__":
    if len(sys.argv) != 2:
        print('unicast_receiver_tcp.py [PORT]')
        exit()
    port = sys.argv[1]
    start_server(int(port))

