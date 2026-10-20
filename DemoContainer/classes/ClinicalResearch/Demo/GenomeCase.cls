/// 基因组精准医疗大用例 · 策展知识图谱后端（贴近真实）。
/// Genome precision-medicine mega use-case · curated knowledge-graph backend (real-world grounded).
/// 
/// 一位示例病人的「基因组 → 诊断 → 用药」一体化图谱，一张 ^GraphData 图贯穿始终，供三种
/// Circos 视图（基因组坐标 / 知识推理 / 用药安全）复用。数据为人工策展、贴近真实：真实基因符号 +
/// 染色体 cytoband 位点，变异用星号等位基因 / rsID，真实通路 / 疾病 / 表型 / 药物，药物基因组
/// 关系按 CPIC / 指南（代谢 / 靶点 / 转运 / HLA 风险 / 禁忌 / 耐药）。
/// One sample patient's unified "genome → diagnosis → therapy" graph over a single ^GraphData graph,
/// reused by three Circos views (genomic coordinate / knowledge reasoning / medication safety). The
/// data is hand-curated and realistic: real gene symbols + chromosome cytoband loci, star-allele / rsID
/// variants, real pathways / diseases / phenotypes / drugs, and CPIC-guideline pharmacogenomic edges.
/// 
/// 节点类型 / node types: PT 病人 patient · V 变异 variant · G 基因 gene · PW 通路 pathway ·
///   D 疾病 disease · HP 表型 phenotype · RX 药物 drug.
/// 关系 / relations: 携带 carries · 位于基因 located_in · 参与通路 participates_in ·
///   关联疾病 associated_with · 表现为 manifests_as · 代谢/靶点/转运/HLA风险/禁忌/耐药 · 融合 fusion.
/// 
/// 用法 / Usage (NEHR):
///   Do ##class(ClinicalResearch.Demo.GenomeCase).Setup()      // 构建策展图谱 / build the curated graph
///   Write ##class(ClinicalResearch.Demo.GenomeCase).FullJSON() // 供页面消费 / graph JSON for the page
///   Do ##class(ClinicalResearch.Demo.GenomeCase).Clear()      // 清理 / cleanup
/// 
/// Author: QP
/// Version: 1.0
/// Last Modified Date: 2026/08/10
Class ClinicalResearch.Demo.GenomeCase Extends %RegisteredObject
{

/// 图节点「类名」标签——仅用于构造图 OID 与定向清理，不需要真实持久类。
/// Node "class" tag for graph OIDs and scoped cleanup; no real persistent class required.
Parameter NODECLS = "GenomeCase.Node";

/// 构建策展的基因组知识图谱（幂等：先 Clear 再重建）。返回物化的有向边数。
/// Build the curated genomic KG (idempotent: Clear then rebuild). Returns the directed edge count.
ClassMethod Setup(pVerbose As %Boolean = 1) As %Integer
{
    Try {
        Do ..Clear()
        Set tT0 = $ZHorolog

        // ---- 基因 / genes: symbol^chr^locus^function ----
        Set tGenes = $ListBuild("CYP2C9^10^10q23.33^药物代谢酶 CYP450", "VKORC1^16^16p11.2^华法林靶点 VKOR", "CYP2C19^10^10q23.33^药物代谢酶 CYP450", "CYP2D6^22^22q13.2^药物代谢酶 CYP450", "TPMT^6^6p22.3^硫嘌呤甲基转移酶")
        Set tGenes = tGenes _ $ListBuild("NUDT15^13^13q14.2^核苷二磷酸酶", "DPYD^1^1p21.3^二氢嘧啶脱氢酶", "SLCO1B1^12^12p12.1^肝摄取转运体 OATP1B1", "HLA-B^6^6p21.33^人类白细胞抗原 I类", "UGT1A1^2^2q37.1^葡糖醛酸转移酶")
        Set tGenes = tGenes _ $ListBuild("G6PD^X^Xq28^葡萄糖-6-磷酸脱氢酶", "BCR^22^22q11.23^断裂点簇集区", "ABL1^9^9q34.12^酪氨酸激酶", "EGFR^7^7p11.2^表皮生长因子受体", "EML4^2^2p21^微管相关蛋白")
        Set tGenes = tGenes _ $ListBuild("ALK^2^2p23.2^间变性淋巴瘤激酶", "KRAS^12^12p12.1^GTP酶 RAS", "BRCA1^17^17q21.31^DNA修复 HRR", "BRCA2^13^13q13.1^DNA修复 HRR", "TP53^17^17p13.1^抑癌基因", "MTHFR^1^1p36.22^叶酸代谢酶")
        For tI = 1:1:$ListLength(tGenes) {
            Set tR = $ListFromString($List(tGenes, tI), "^")
            Do ..node("G", $ListGet(tR, 1), $ListGet(tR, 2), $ListGet(tR, 3), $ListGet(tR, 4))
        }

        // ---- 变异 / variants: symbol^rsid^gene^effect^zygosity ----
        Set tVars = $ListBuild("CYP2C9*2^rs1799853^CYP2C9^中间代谢 IM^杂合 het", "CYP2C9*3^rs1057910^CYP2C9^慢代谢 PM^纯合 hom", "VKORC1 -1639G>A^rs9923231^VKORC1^华法林高敏 sensitive^纯合 hom")
        Set tVars = tVars _ $ListBuild("CYP2C19*2^rs4244285^CYP2C19^慢代谢 PM(LOF)^杂合 het", "CYP2C19*17^rs12248560^CYP2C19^超快代谢 UM(GOF)^杂合 het", "CYP2D6*4^rs3892097^CYP2D6^慢代谢 PM^杂合 het")
        Set tVars = tVars _ $ListBuild("TPMT*3C^rs1142345^TPMT^功能缺失 LOF^杂合 het", "NUDT15*3^rs116855232^NUDT15^功能缺失 LOF^杂合 het", "DPYD*2A^rs3918290^DPYD^功能缺失 LOF^杂合 het")
        Set tVars = tVars _ $ListBuild("SLCO1B1*5^rs4149056^SLCO1B1^转运降低 decreased^杂合 het", "HLA-B*57:01^HLA-B*57:01^HLA-B^阿巴卡韦超敏风险 risk^阳性 pos", "HLA-B*15:02^HLA-B*15:02^HLA-B^卡马西平SJS风险 risk^阳性 pos")
        Set tVars = tVars _ $ListBuild("UGT1A1*28^rs8175347^UGT1A1^葡糖醛酸化降低 decreased^纯合 hom", "G6PD Mediterranean^rs5030868^G6PD^酶缺乏 deficiency^半合子 hemi", "EGFR L858R^rs121434568^EGFR^激活突变 activating^体细胞 somatic")
        Set tVars = tVars _ $ListBuild("KRAS G12D^rs121913529^KRAS^激活突变 activating^体细胞 somatic", "BRCA1 185delAG^rs386833395^BRCA1^致病 pathogenic^杂合 het", "BRCA2 6174delT^-^BRCA2^致病 pathogenic^杂合 het", "TP53 R175H^rs28934578^TP53^致病 pathogenic^体细胞 somatic")
        For tI = 1:1:$ListLength(tVars) {
            Set tR = $ListFromString($List(tVars, tI), "^")
            Do ..variant($ListGet(tR, 1), $ListGet(tR, 2), $ListGet(tR, 3), $ListGet(tR, 4), $ListGet(tR, 5))
        }

        // ---- 基因融合 / gene fusions: geneA^geneB^label（跨染色体弦，view A 亮点）----
        Set tFus = $ListBuild("BCR^ABL1^融合 BCR-ABL1 t(9;22)", "EML4^ALK^融合 EML4-ALK inv(2)")
        For tI = 1:1:$ListLength(tFus) {
            Set tR = $ListFromString($List(tFus, tI), "^")
            Do ..addEdge(..sym("G", $ListGet(tR, 1)), ..sym("G", $ListGet(tR, 2)), $ListGet(tR, 3))
        }

        // ---- 基因→通路 / gene participates_in pathway ----
        Set tGP = $ListBuild("CYP2C9^华法林代谢与维生素K循环 Warfarin/VitK", "VKORC1^华法林代谢与维生素K循环 Warfarin/VitK", "VKORC1^凝血级联 Coagulation", "CYP2C9^细胞色素P450药物代谢 CYP450", "CYP2C19^细胞色素P450药物代谢 CYP450", "CYP2D6^细胞色素P450药物代谢 CYP450")
        Set tGP = tGP _ $ListBuild("TPMT^硫嘌呤代谢 Thiopurine", "NUDT15^硫嘌呤代谢 Thiopurine", "DPYD^氟嘧啶代谢 Fluoropyrimidine", "MTHFR^叶酸代谢 Folate", "SLCO1B1^他汀转运与脂代谢 Statin/Lipid", "HLA-B^免疫应答与HLA呈递 Immune/HLA")
        Set tGP = tGP _ $ListBuild("UGT1A1^葡糖醛酸结合 Glucuronidation", "G6PD^磷酸戊糖途径 Pentose phosphate", "BCR^BCR-ABL信号 BCR-ABL signaling", "ABL1^BCR-ABL信号 BCR-ABL signaling", "EGFR^EGFR信号 EGFR signaling", "EGFR^RAS-MAPK信号 RAS-MAPK")
        Set tGP = tGP _ $ListBuild("ALK^RAS-MAPK信号 RAS-MAPK", "EML4^RAS-MAPK信号 RAS-MAPK", "KRAS^RAS-MAPK信号 RAS-MAPK", "BRCA1^同源重组修复 HR repair", "BRCA2^同源重组修复 HR repair", "TP53^同源重组修复 HR repair")
        For tI = 1:1:$ListLength(tGP) {
            Set tR = $ListFromString($List(tGP, tI), "^")
            Do ..addEdge(..sym("G", $ListGet(tR, 1)), ..node("PW", $ListGet(tR, 2)), "参与通路 participates_in")
        }

        // ---- 基因→疾病 / gene associated_with disease ----
        Set tGD = $ListBuild("CYP2C9^静脉血栓栓塞 VTE", "VKORC1^静脉血栓栓塞 VTE", "CYP2C19^急性冠脉综合征 ACS", "TPMT^硫嘌呤骨髓抑制 Thiopurine myelosuppression", "NUDT15^硫嘌呤骨髓抑制 Thiopurine myelosuppression", "DPYD^氟嘧啶毒性 Fluoropyrimidine toxicity")
        Set tGD = tGD _ $ListBuild("SLCO1B1^他汀肌病 Statin myopathy", "HLA-B^重症皮肤不良反应 SJS/TEN", "G6PD^G6PD缺乏溶血 G6PD hemolysis", "BCR^慢性髓性白血病 CML", "ABL1^慢性髓性白血病 CML", "EGFR^非小细胞肺癌 NSCLC")
        Set tGD = tGD _ $ListBuild("ALK^非小细胞肺癌 NSCLC", "EML4^非小细胞肺癌 NSCLC", "KRAS^结直肠癌 Colorectal cancer", "BRCA1^遗传性乳腺卵巢癌 HBOC", "BRCA2^遗传性乳腺卵巢癌 HBOC", "TP53^遗传性乳腺卵巢癌 HBOC")
        For tI = 1:1:$ListLength(tGD) {
            Set tR = $ListFromString($List(tGD, tI), "^")
            Do ..addEdge(..sym("G", $ListGet(tR, 1)), ..node("D", $ListGet(tR, 2)), "关联疾病 associated_with")
        }

        // ---- 疾病→表型 / disease manifests_as phenotype ----
        Set tDH = $ListBuild("静脉血栓栓塞 VTE^出血风险 Bleeding risk", "静脉血栓栓塞 VTE^血栓形成 Thrombosis", "急性冠脉综合征 ACS^支架内血栓 Stent thrombosis", "急性冠脉综合征 ACS^疗效降低 Reduced efficacy", "慢性髓性白血病 CML^白细胞增多 Leukocytosis", "非小细胞肺癌 NSCLC^肿瘤进展 Tumor progression")
        Set tDH = tDH _ $ListBuild("结直肠癌 Colorectal cancer^抗EGFR耐药 Anti-EGFR resistance", "遗传性乳腺卵巢癌 HBOC^肿瘤易感 Cancer predisposition", "硫嘌呤骨髓抑制 Thiopurine myelosuppression^中性粒细胞减少 Neutropenia", "硫嘌呤骨髓抑制 Thiopurine myelosuppression^骨髓抑制 Myelosuppression")
        Set tDH = tDH _ $ListBuild("氟嘧啶毒性 Fluoropyrimidine toxicity^严重毒性 Severe toxicity", "氟嘧啶毒性 Fluoropyrimidine toxicity^黏膜炎 Mucositis", "他汀肌病 Statin myopathy^肌病 Myopathy", "他汀肌病 Statin myopathy^横纹肌溶解 Rhabdomyolysis", "重症皮肤不良反应 SJS/TEN^超敏反应 Hypersensitivity", "G6PD缺乏溶血 G6PD hemolysis^溶血性贫血 Hemolytic anemia")
        For tI = 1:1:$ListLength(tDH) {
            Set tR = $ListFromString($List(tDH, tI), "^")
            Do ..addEdge(..node("D", $ListGet(tR, 1)), ..node("HP", $ListGet(tR, 2)), "表现为 manifests_as")
        }

        // ---- 基因→药物 / gene-drug pharmacogenomic edges: gene^drug^relation ----
        Set tGR = $ListBuild("CYP2C9^华法林 Warfarin^代谢 metabolizes", "VKORC1^华法林 Warfarin^靶点 target", "CYP2C9^苯妥英 Phenytoin^代谢 metabolizes", "CYP2C19^氯吡格雷 Clopidogrel^代谢激活 activates", "CYP2D6^可待因 Codeine^代谢 metabolizes", "CYP2D6^他莫昔芬 Tamoxifen^代谢 metabolizes")
        Set tGR = tGR _ $ListBuild("TPMT^硫唑嘌呤 Azathioprine^代谢 metabolizes", "NUDT15^硫唑嘌呤 Azathioprine^代谢 metabolizes", "TPMT^巯嘌呤 6-MP^代谢 metabolizes", "NUDT15^巯嘌呤 6-MP^代谢 metabolizes", "DPYD^氟尿嘧啶 Fluorouracil^代谢 metabolizes", "DPYD^卡培他滨 Capecitabine^代谢 metabolizes")
        Set tGR = tGR _ $ListBuild("SLCO1B1^辛伐他汀 Simvastatin^转运 transports", "HLA-B^阿巴卡韦 Abacavir^HLA风险 HLA-risk", "HLA-B^卡马西平 Carbamazepine^HLA风险 HLA-risk", "UGT1A1^伊立替康 Irinotecan^代谢 metabolizes", "G6PD^拉布立海 Rasburicase^禁忌 contraindicated", "G6PD^伯氨喹 Primaquine^禁忌 contraindicated")
        Set tGR = tGR _ $ListBuild("ABL1^伊马替尼 Imatinib^靶点 target", "EGFR^吉非替尼 Gefitinib^靶点 target", "EGFR^厄洛替尼 Erlotinib^靶点 target", "ALK^克唑替尼 Crizotinib^靶点 target", "BRCA1^奥拉帕尼 Olaparib^靶点 target", "BRCA2^奥拉帕尼 Olaparib^靶点 target", "KRAS^西妥昔单抗 Cetuximab^耐药标志 resistance", "MTHFR^甲氨蝶呤 Methotrexate^代谢 metabolizes")
        For tI = 1:1:$ListLength(tGR) {
            Set tR = $ListFromString($List(tGR, tI), "^")
            Do ..addEdge(..sym("G", $ListGet(tR, 1)), ..node("RX", $ListGet(tR, 2)), $ListGet(tR, 3))
        }

        // ---- 病人 + 携带的变异 / patient and carried variants ----
        Set tPid = ..node("PT", "病人 P001 · 示例基因组", "", "", "多基因药物基因组型 multi-gene PGx genotype", "")
        Set ^GenomeCase.Meta("patient") = tPid
        Set tCarry = $ListBuild("CYP2C9*3", "VKORC1 -1639G>A", "CYP2C19*2", "SLCO1B1*5", "TPMT*3C", "DPYD*2A", "HLA-B*57:01", "BRCA1 185delAG")
        For tI = 1:1:$ListLength(tCarry) {
            Do ..addEdge(tPid, ..sym("V", $List(tCarry, tI)), "携带 carries")
        }

        Set tNE = +$Get(^GenomeCase.Meta("edges")), tNN = +$Get(^GenomeCase.Meta("nodes"))
        Write:pVerbose "构建完成 built genome case: ", tNN, " nodes, ", tNE, " directed edges  用时/time=", $FNumber($ZHorolog - tT0, "", 3), "s", !
        Return tNE
    }
    Catch tEx {
        Write "构建失败 Setup failed: ", tEx.DisplayString(), !
        Return -1
    }
}

/// 创建（或复用）一个节点，按 (type,name) 去重；返回节点 id。
/// Create (or reuse) a node deduped by (type,name); returns the node id.
ClassMethod node(pType As %String, pName As %String, pChr As %String = "", pLocus As %String = "", pNote As %String = "", pEff As %String = "") As %Integer [ Private ]
{
    Try {
        Set tId = +$Get(^GenomeCase.Sym(pType, pName))
        If tId > 0 Return tId
        Set tId = $Increment(^GenomeCase.Meta("seq"))
        Set ^GenomeCase.N(tId) = $ListBuild(pType, pName, pChr, pLocus, pNote, pEff)
        Set ^GenomeCase.Sym(pType, pName) = tId
        Set ^GenomeCase.Meta("nodes") = +$Get(^GenomeCase.Meta("nodes")) + 1
        Return tId
    }
    Catch tEx { Return 0 }
}

/// 创建一个变异节点（染色体/位点继承所属基因），并连一条 变异→基因 located_in 边；返回变异 id。
/// Create a variant node (chr/locus inherited from its gene) and a variant→gene located_in edge.
ClassMethod variant(pSym As %String, pRsid As %String, pGeneSym As %String, pEff As %String, pZyg As %String) As %Integer [ Private ]
{
    Try {
        Set tGid = ..sym("G", pGeneSym)
        If 'tGid Return 0
        Set tG = $Get(^GenomeCase.N(tGid))
        Set tVid = ..node("V", pSym, $ListGet(tG, 3), $ListGet(tG, 4), pRsid _ " · " _ pZyg, pEff)
        Do ..addEdge(tVid, tGid, "位于基因 located_in")
        Return tVid
    }
    Catch tEx { Return 0 }
}

/// 写一条有向边：进 ^GenomeCase.E（关系标签）与图全局 OUT/IN（供 BFS/遍历）。去重返回 1，重复返回 0。
/// Write one directed edge into ^GenomeCase.E (relation label) and the graph globals OUT/IN.
ClassMethod addEdge(pSrc As %Integer, pTgt As %Integer, pRel As %String) As %Integer [ Private ]
{
    Try {
        If (pSrc '> 0) || (pTgt '> 0) Return 0
        If $Data(^GenomeCase.E(pSrc, pTgt)) Return 0
        Set tCls = ..#NODECLS
        Set ^GenomeCase.E(pSrc, pTgt) = pRel
        Set ^GraphData.OUT("User", $ListBuild(pSrc, tCls), $ListBuild(pTgt, tCls), pRel) = ""
        Set ^GraphData.IN("User", $ListBuild(pTgt, tCls), $ListBuild(pSrc, tCls), pRel) = ""
        Set ^GenomeCase.Meta("edges") = +$Get(^GenomeCase.Meta("edges")) + 1
        Return 1
    }
    Catch tEx { Return 0 }
}

/// 按 (type,name) 查已存在节点 id（不存在返回 0）。
/// Look up an existing node id by (type,name); 0 if absent.
ClassMethod sym(pType As %String, pName As %String) As %Integer [ Private ]
{
    Quit +$Get(^GenomeCase.Sym(pType, pName))
}

/// 清理本用例数据：只删 GenomeCase.Node 键的图边，再清空本地全局。绝不触碰其它图。
/// Cleanup: remove only this case's GenomeCase.Node graph edges, then clear local globals.
ClassMethod Clear()
{
    Try {
        Set tCls = ..#NODECLS, tK = ""
        For { Set tK = $Order(^GraphData.OUT("User", tK))  Quit:tK=""  If $ListValid(tK), $ListGet(tK, 2) = tCls { Kill ^GraphData.OUT("User", tK) } }
        Set tK = ""
        For { Set tK = $Order(^GraphData.IN("User", tK))   Quit:tK=""  If $ListValid(tK), $ListGet(tK, 2) = tCls { Kill ^GraphData.IN("User", tK) } }
        Kill ^GenomeCase.N, ^GenomeCase.E, ^GenomeCase.Sym, ^GenomeCase.Meta
    }
    Catch tEx {}
}

/// 数据是否已装载 / whether data is loaded.
ClassMethod HasData() As %Boolean
{
    Quit ..NodeCount() > 0
}

/// 节点总数 / total node count.
ClassMethod NodeCount() As %Integer
{
    Quit +$Get(^GenomeCase.Meta("nodes"))
}

/// 有向边总数 / total directed edge count.
ClassMethod EdgeCount() As %Integer
{
    Quit +$Get(^GenomeCase.Meta("edges"))
}

/// 示例病人节点 id / sample patient node id.
ClassMethod PatientId() As %Integer
{
    Quit +$Get(^GenomeCase.Meta("patient"))
}

/// 输出整张策展图为 JSON：{nodes:[{id,ty,name,chr,locus,note,eff}],edges:[{s,t,r}],patient:<id>}。
/// Emit the whole curated graph as JSON for the page to consume.
ClassMethod FullJSON() As %String
{
    Try {
        Set tNodes = "[", tFirst = 1, tId = ""
        For {
            Set tId = $Order(^GenomeCase.N(tId))  Quit:tId=""
            Set tR = ^GenomeCase.N(tId)
            Set:'tFirst tNodes = tNodes _ ","
            Set tFirst = 0
            Set tNodes = tNodes _ "{""id"":" _ tId _ ",""ty"":""" _ $ListGet(tR, 1) _ """,""name"":""" _ ..esc($ListGet(tR, 2)) _ """,""chr"":""" _ ..esc($ListGet(tR, 3)) _ """,""locus"":""" _ ..esc($ListGet(tR, 4)) _ """,""note"":""" _ ..esc($ListGet(tR, 5)) _ """,""eff"":""" _ ..esc($ListGet(tR, 6)) _ """}"
        }
        Set tNodes = tNodes _ "]"
        Set tEdges = "[", tFirst = 1, tS = ""
        For {
            Set tS = $Order(^GenomeCase.E(tS))  Quit:tS=""
            Set tT = ""
            For {
                Set tT = $Order(^GenomeCase.E(tS, tT))  Quit:tT=""
                Set:'tFirst tEdges = tEdges _ ","
                Set tFirst = 0
                Set tEdges = tEdges _ "{""s"":" _ tS _ ",""t"":" _ tT _ ",""r"":""" _ ..esc(^GenomeCase.E(tS, tT)) _ """}"
            }
        }
        Set tEdges = tEdges _ "]"
        Return "{""nodes"":" _ tNodes _ ",""edges"":" _ tEdges _ ",""patient"":" _ ..PatientId() _ "}"
    }
    Catch tEx {
        Return "{""nodes"":[],""edges"":[],""patient"":0,""err"":""" _ ..esc(tEx.DisplayString()) _ """}"
    }
}

/// JSON 字符串转义 / JSON string escaping.
ClassMethod esc(pS As %String) As %String [ Private ]
{
    Set pS = $Replace(pS, "\", "\\")
    Set pS = $Replace(pS, """", "\""")
    Set pS = $Replace(pS, $Char(10), "\n")
    Set pS = $Replace(pS, $Char(13), "")
    Quit pS
}

}
