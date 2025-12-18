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

En este apartado