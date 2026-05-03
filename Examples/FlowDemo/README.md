# FlowDemo

A small four-way traffic-light scenario for exercising SumoGUIMac with steady traffic flow.

Open this file in SumoGUIMac:

```sh
Examples/FlowDemo/flowdemo.sumocfg
```

The route file defines several `<flow>` entries with cars and buses crossing the intersection from different approaches. The network is generated from `flowdemo.nod.xml` and `flowdemo.edg.xml` using SUMO `netconvert`.

To regenerate the network:

```sh
netconvert --node-files flowdemo.nod.xml --edge-files flowdemo.edg.xml --output-file flowdemo.net.xml --tls.guess true --no-turnarounds true
```
