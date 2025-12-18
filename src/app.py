import os
import random
import sys
import threading
import time
import requests
import signal
from kazoo.client import KazooClient
from kazoo.recipe.election import Election
from kazoo.recipe.watchers import DataWatch, ChildrenWatch
from kazoo.exceptions import NoNodeError, ZookeeperError, NodeExistsError, ConnectionClosedError


ZOOKEEPER_HOST = os.getenv("ZOOKEEPER_HOST", "127.0.0.1:2181")
SAMPLING_PERIOD = int(os.getenv("SAMPLING_PERIOD", 5))
API_URL = os.getenv("API_URL", "http://localhost:8080/nuevo")

# client is declared global so that the connection 
# can be stopped properly inside interrupt_handler
client = None

def interrupt_handler(signal, frame):
    print("\nInterrupt received")
    if client:
        client.stop()
    sys.exit(0)

signal.signal(signal.SIGINT, interrupt_handler)




def watch_devices(children):
    print(f"[WATCHER] Connected devices: {children}")
    return True # Keep the watcher active


def watch_sampling_period(data, stat):
    global SAMPLING_PERIOD
    if data:
        try:
            SAMPLING_PERIOD = int(data.decode('utf-8'))
            print(f"[WATCHER] sampling_period value: {SAMPLING_PERIOD} seconds")
        except ValueError:
            print(f"ERROR: Incorrect value type for SAMPLING_PERIOD: {SAMPLING_PERIOD}")
            pass

    return True # Keep the watcher alive


def watch_api_url(data, stat):
    global API_URL
    if data:
        API_URL = data.decode('utf-8')
        print(f"[WATCHER] API_URL value: {API_URL}")
    
    return True # Keep the watcher alive




def leader_func(id: int, client: KazooClient):
    """Function that computes the mean of all the measures and sends it to the API.
    
    Args:
        id (int): id of the leader process.
        client (KazooClient): client used to connect to Zookeeper
    
    Note that this function is only executed by the leader process 
    """

    # Watch for creations/deletions of nodes under "/mediciones"
    ChildrenWatch(client, "/mediciones", watch_devices)

    while True:
        print(f"I'm the leader: (id = {id})")
        try:
            children = client.get_children("/mediciones")
        except ConnectionClosedError:
            break
        values = []
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
                requests.get(API_URL, params={"dato": mean}, timeout=2)
            except requests.RequestException as e:
                print(f"ERROR: Failed to contact API: {e}")

        time.sleep(SAMPLING_PERIOD)


def generate_random_measures(id: int, client: KazooClient):
    """Generate random measures and write them to a znode

    Args:
        id (int): id of the process running this function
        client (KazooClient): client used to connect to Zookeeper
    """
    while True:
        value = random.randint(75, 85)
        path = f"/mediciones/{id}"
        
        try:
            try:
                client.create(path, str(value).encode('utf-8'), ephemeral=True)
            except NodeExistsError:
                client.set(path, str(value).encode('utf-8'))
        except ConnectionClosedError:
            break

        time.sleep(SAMPLING_PERIOD)




def main():

    if len(sys.argv) != 2:
        print("Usage: python3 app.py <id>")
        sys.exit(1)

    id = int(sys.argv[1])

    # Connect to Zookeeper service
    global client
    client = KazooClient(hosts=ZOOKEEPER_HOST)
    client.start()
    
    
    # Create the node "/config" if it doesn't exist
    client.ensure_path("/config")

    # Watch for changes on sampling_period and api_url nodes under "/config"
    DataWatch(client, "/config/sampling_period", watch_sampling_period)
    DataWatch(client, "/config/api_url", watch_api_url)

    
    # Create the node "/mediciones" if it doesn't exist
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
    try:
        election.run(leader_func, id, client)
    except ConnectionClosedError:
        pass


if __name__ == "__main__":
    main()