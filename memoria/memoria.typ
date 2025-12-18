#set page(
  paper: "a4",
  header: align(left)[
    Desarrollo de Software Crítico
  ],
  numbering: "1",
)

#set text(
  font: "New Computer Modern",
  size: 11pt
)

// Switch to Cascadia Code for both
// inline and block raw.
#show raw: set text(font: "Cascadia Mono")

// Reset raw blocks to the same size as normal text,
// but keep inline raw at the reduced size.
//#show raw.where(block: true): set text(1em / 0.8)

#show title: set text(size: 17pt)
#show title: set align(center)
#show title: set block(below: 1.2em)

#title[
  Desarrollo de un sistema distribuido con Zookeeper
]

#align(center)[
  Carlos García Guzmán \
  Universidad de Málaga \
  #link("mailto:carlosgarciag552@uma.es")
]

#set heading(numbering: "1.")

//Table of contents
#outline()

= Funcionamiento básico del sistema

Se ha desarrollado una solución en Python `src/app.py` que orquesta un conjunto de nodos sensores coordinados mediante *Apache ZooKeeper*, concretamente a través de la librería `kazoo` disponible para Python.

El sistema se compone de un conjunto de nodos que se comunican con un servidor *ZooKeeper* para coordinar sus acciones. Cada nodo se identifica con un ID único y realiza dos funciones principales: actuar como sensor y participar en un proceso de elección de líder.

== Lógica de la Aplicación
Tal como se acaba de mencionar, cada nodo/instancia de la aplicación realiza dos funciones concurrentes:
1.  *Sensor (Thread secundario)*: Genera mediciones aleatorias cada 5 segundos y las publica en ZooKeeper. Se utilizan *znodes efímeros* en la ruta `/mediciones/app{id}`, asegurando que las mediciones de un nodo solo existan mientras dure la sesión de ese nodo.
2.  *Coordinador/Elección (Thread principal):* Utilizando la receta `Election` de la librería `kazoo`. El nodo escogido como líder es el encargado de recolectar los datos que escriben todos los nodos (incluido él) y enviarlos a la API desarrollada en la práctica anterior.

== Funcionalidad del Líder
El líder ejecuta un bucle infinito donde:
- Recupera la lista de nodos hijos en `/mediciones`.
- Lee el valor de cada nodo, gestionando posibles condiciones de carrera (nodos que se desconectan durante la lectura).
- Calcula la media aritmética de los valores disponibles.
- Envía el resultado a una API externa `http://localhost:8080/nuevo?dato=valor`

== Robustez
El código incluye manejo de señales (`SIGINT`) para un cierre ordenado de la conexión con ZooKeeper y bloques `try-except` para gestionar errores de red al comunicar con la API o inconsistencias temporales en los datos de ZooKeeper.

== Ejemplo de ejecución inicial
Antes de probar la correcta ejecución del sistema nos debemos asegurar de que tenemos un contenedor ejecutando Zookeeper, así como otro que ejecute la API desarrollada en la práctica anterior (por simplicidad, en esta sección usaremos el fichero  `compose-inicial.yaml`, el cual se encarga de ejecutar tanto nuestra API como zookeeper):

```bash docker compose -f compose-inicial.yaml up```

Si ahora ejecutamos varias instancias de nuestra app podemos observar que una de ellas es escogida como lider, como se puede observar en @ejecucion-inicial1:

#figure(
  image("images/ejecucion-inicial1.png", width: 100%),
  caption: [
    Ejecución simple de $N=2$ instancias de nuestra aplicación.
  ]
) <ejecucion-inicial1>

Si ahora interrumpimos al lider, podemos ver que automáticamente la otra instancia de la aplicación es elegida como nuevo líder, como se muestra en @ejecucion-inicial2

#figure(
  image("images/ejecucion-inicial2.png", width: 100%),
  caption: [
    Interrupción del lider
  ]
) <ejecucion-inicial2>

Para verificar el correcto funcionamiento de nuestra API, podemos usar el navegador para comprobar que efectivamente todas las medias de las medidas están siendo publicadas, tal como se muestra en @browser-inicial:

#figure(
  image("images/browser-inicial.png", width: 50%),
  caption: [
    Listado de las medias
  ],
  placement: top
) <browser-inicial>

= Utilización de Watchers
En esta fase del desarrollo se han añadido mecanismos de vigilancia (*Watchers*) para dotar al sistema de mayor reactividad y flexibilidad. Se han implementado dos tipos de watchers proporcionados por la librería `kazoo`:

== Monitorización de Dispositivos (`ChildrenWatch`)
El líder ahora tiene la responsabilidad de monitorizar la conexión y desconexión de los nodos sensores. Para ello, se utiliza un `ChildrenWatch` sobre la ruta `/mediciones`. Cada vez que un nodo se conecta/desconecta, el líder mostrará todos los nodos que se encuentran conectados en el momento (nodos cuya sesión sigue activa).

=== Ejemplo de monitorización de dispositivos
Al igual que antes, en @watchers1 se muestra una ejecución que permite ver el funcionamiento de estas nuevas funcionalidades. En este caso podemos ver que al iniciar cada instancia inmediatamente se muestran los valores de `/config/sampling_period` y `/config/api_url`, puesto que este es el funcionamiento por defecto del constructor `DataWatch`, el cual se explicará posteriormente. Además, cuando lanzamos el segundo proceso, el líder lo detecta y muestra por pantalla que efectivamente hay 2 dispositivos conectados. Algo similar ocurre cuando interrumpimos al proceso líder, pues el segundo proceso es escogido como nuevo líder y detecta que ahora ya sólo se encuentra él en el sistema.

#figure(
  image("images/children-watchers.png"),
  caption: [
    Funcionamiento de ChildrenWatch
  ]
) <watchers1>


== Configuración Distribuida (`DataWatch`)
Para evitar tener valores de configuración estáticos o depender únicamente de variables de entorno que requieren reinicios para cambiarse, se ha añadido un sistema de configuración distribuida utilizando `DataWatch`.

Se han definido dos rutas en ZooKeeper para almacenar la configuración:
- `/config/sampling_period`: Controla el tiempo de espera entre mediciones.
- `/config/api_url`: Define la dirección del servidor al que se envían los datos.

Cada nodo instala un `DataWatch` en estas rutas. Cuando un script externo modifica el valor de estos znodes, la función de callback asociada se ejecuta en todos los nodos, actualizando sus variables globales `SAMPLING_PERIOD` o `API_URL` en tiempo real.

=== Ejemplo de configuración distribuida
En este ejemplo se utiliza un único proceso y el fichero `src/init_config.py` para cambiar la configuración del sistema. Mientras el proceso se encuentra en ejecución podemos ejecutar el anterior fichero de la siguiente forma: 

```bash python3 src/init_config.py 6 http://localhost:8081/nuevo```

Esta nueva configuración lleva al sistema a un estado de error, puesto que la API escucha peticiones en el puerto 8080. Esta interacción se puede ver en la siguiente @watchers2:

#figure(
  image("images/data-watchers.png"),
  caption: [
    Funcionamiento de ChildrenWatch
  ]
) <watchers2>

= Sincronización Avanzada
En esta iteración sobre el diseño del sistema, se ha modificado la arquitectura para utilizar primitivas de sincronización más avanzadas, sustituyendo los temporizadores locales independientes por una coordinación centralizada mediante barreras.

== Barreras (`Barrier`)
Se ha implementado una barrera simple `/barrier` para sincronizar el ciclo de medición de todos los dispositivos:
- *Dispositivos*: Tras enviar su medición, se quedan bloqueados esperando en la barrera `barrier.wait()` en lugar de esperar el tiempo `SAMPLING_PERIOD`.
- *Líder*: Es el encargado de controlar el ritmo. Crea la barrera al inicio del ciclo, espera el tiempo de muestreo `SAMPLING_PERIOD`, procesa los datos y finalmente elimina la barrera `barrier.remove()`, liberando a todos los dispositivos simultáneamente para la siguiente iteración.

Esto garantiza que el procesamiento del líder ocurra mientras los dispositivos están en espera, y que todos comiencen el siguiente ciclo a la vez.

== Contador Distribuido (`Counter`)
Adicionalmente, se ha incorporado un contador distribuido `/counter` para llevar un registro global del número de mediciones realizadas por el clúster. Cada dispositivo incrementa este contador atómicamente `counter += 1` antes de esperar en la barrera.

Cabe destacar que, aunque el incremento en ZooKeeper es atómico y consistente, la impresión por pantalla del valor puede mostrar condiciones de carrera visuales (varios nodos imprimiendo el mismo número). Este problema se podría solucionar fácilmente adquiriendo un *lock* y no soltarlo hasta que se imprima el valor.  

En la siguiente imagen @counter, se muestra un ejemplo en el que se puede apreciar cómo ambos procesos incrementan el contador. El sistema sigue siendo tolerante a fallos de los nodos pues la elección automática de líder sigue funcionando correctamente.

#figure(
  image("images/counter-example.png"),
  caption: [
    Funcionamiento del contador
  ]
) <counter>

