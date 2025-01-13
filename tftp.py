from tftpy import TftpServer
import sys
def start_tftp_server(directory, u_host='0.0.0.0', u_port=69):
    """
    Startet einen einfachen TFTP-Server.
    :param directory: Verzeichnis für TFTP-Dateien
    :param host: IP-Adresse, auf der der Server läuft (Standard: alle Schnittstellen)
    :param port: Port für TFTP (Standard: 69)
    """
    print(f"Starte TFTP-Server auf {u_host}:{u_port}, Verzeichnis: {directory}")
    server = TftpServer(directory)
    try:
        server.listen()
    except PermissionError:
        print("Fehler: Sie benötigen Administratorrechte, um Port 69 zu verwenden.")
        print("Führen Sie das Skript als Administrator aus oder verwenden Sie einen anderen Port.")
    except KeyboardInterrupt:
        print("\nTFTP-Server beendet.")

if __name__ == "__main__":
    # Pfad zum Verzeichnis mit Dateien, die für den TFTP-Zugriff verfügbar sein sollen
    tftp_directory = sys.argv[1] # Ersetzen Sie dies durch Ihren Verzeichnis-Pfad
    start_tftp_server(tftp_directory)
