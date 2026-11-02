本次夹具来源：

- `context-never-activated.bridge.json` 已与 relay 副本同名文件逐字节哈希核对一致，保留既有文件；补拷同目录的 `context-never-activated.relay.json`。
- `cxgov-*.json` 由 relay 副本 `docs/CX-GOV-1-RESULT.md` 第 1 至 4 节 JSON 样本提取，脚本为 `_cxgov/prepare-fixtures.ps1`。它们是文档样本，不冒称新的真实服务端导出。
- 当前 relay 副本的 Flutter 夹具目录只提供上述 never-activated 两个文件，没有星级、成员角色或审计的新增导出。测试将文档中的 relay targetSubject 投影为 Host targetRef，并为旧角色模板样本补上同文档列明的 policyV2 行字段。
- 端口测试通过既有内存 Bridge 编解码发送这些样本，也显式去掉 null 键。没有向真实 Host、relay 或合作方发请求。
