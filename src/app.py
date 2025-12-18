import os
import random
import sys
import threading
import time
import requests
import signal
from kazoo.client import KazooClient
from kazoo.recipe.election import Election
from kazoo.exceptions import NoNodeError, ZookeeperError, NodeExistsError


# Client is declared globally so that the interrupt_handler can stop it
client = None

def interrupt_handler(signal, frame):
    if client:
        client.stop()
    exit(0)

signal.signal(signal.SIGINT, interrupt_handler)



def leader_func(id: int, client: KazooClient):
    """Function that computes the mean of all the measures and sends it to the API.
    
    Args:
        id (int): id of the leader process.
        client (KazooClient): client used to connect to Zookeeper
    
    Note that this function is only executed by the leader process 
    """
    while True:
        print(f"I'm the leader: (id = {id})")
        children = client.get_children("/mediciones")
        values = []
        print(f"Measures to compute the mean: /mediciones/{children}")
        for child in children:
            try:
                data, _ = client.get(f"/mediciones/{child}")
                values.append(float(data.decode('utf-8')))
            except (ValueError, TypeError):
                print(f"ERROR: Invalid data format in node {child}")
            except NoNodeError as e:
                print("ERROR: get of a node that does not exist.")
                print(e)
            except ZookeeperError as e:
                print("ERROR: the server returned a non-zero error code.")
                print(e)
        
        if values:
            mean = sum(values) / len(values)
            print(f"Media: {mean}")
            try:
                requests.get("http://127.0.0.1:80/nuevo", params={"dato": mean}, timeout=2)
            except requests.RequestException as e:
                print(f"ERROR: Failed to contact API: {e}")

        time.sleep(5)


def generate_random_measures(id: int, client: KazooClient):
    """Generate random measures and write them to a znode

    Args:
        id (int): id of the process running this function
        client (KazooClient): client used to connect to Zookeeper
    """
    while True:
        value = random.randint(75, 85)
        path = f"/mediciones/app{id}"
        try:
            client.create(path, str(value).encode('utf-8'), ephemeral=True)
        except NodeExistsError:
            client.set(path, str(value).encode('utf-8'))
        
        time.sleep(5)


def main():
    argc = len(sys.argv)
    if argc != 2:
        print("ERROR: Missing app instance id.\nUsage: python3 app.py <id>")
        sys.exit(1)

    id = int(sys.argv[1])
    global client
    
    client = KazooClient(hosts="127.0.0.1:2181")
    client.start()
    
    # Create a node /mediciones if it doesn't exist
    client.ensure_path("/mediciones")
    
    # Create a thread that infinitely generates random measures
    measures_thread = threading.Thread(
        target=generate_random_measures, 
        daemon=True,
        args=(id, client)
    )
    measures_thread.start()

    
    # Vote for a leader among all our app instances
    election = Election(client, "/election", id)
    election.run(leader_func, id, client)



if __name__ == "__main__":
    main()