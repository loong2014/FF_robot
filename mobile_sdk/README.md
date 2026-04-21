# mobile_sdk

Flutter 侧 SDK，提供统一控制入口：

- `connectBLE()`
- `connectTCP()`
- `connectMQTT()`
- `move() / stand() / sit() / stop()`
- `stateStream`

内部包含：

- 统一协议编解码
- `latest move + discrete FIFO` 命令队列
- ACK / 重传逻辑
- TCP 可用实现
- BLE / MQTT 接口占位，方便接入具体插件

