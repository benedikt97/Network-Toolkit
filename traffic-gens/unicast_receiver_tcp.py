import socket
import sys

def start_server(port):
    host = ''
    # Erstelle einen TCP/IP-Socket
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

    # Binde den Socket an die Adresse und den Port
    server_socket.bind((host, port))

    # Warte darauf, dass ein Client eine Verbindung herstellt
    server_socket.listen()

    print(f"Server läuft auf {host}:{port}, warte auf Verbindungen...")

    while True:
        # Warte auf eine neue Verbindung
        client_socket, client_address = server_socket.accept()
        print(f"Verbindung von {client_address} angenommen.")

        # Empfange Daten vom Client
        while True:
            data = client_socket.recv(1024).decode('utf-8')
            print(f"Empfangene Daten: {data}")


        # Schließe die Verbindung zum Client
        client_socket.close()

# Start des Servers
if __name__ == "__main__":
    port = sys.argv[1]
    start_server(int(port))

