/// 接触追踪的**人-人接触边**表（纯 SQL 基线的关系型表示）：A 与 B 于时间 Ct 在地点 LocId 接触。
/// Person-person CONTACT edge table (the relational baseline): A and B contacted at time Ct, place LocId.
/// 
/// 由 CTPresence 的「同地点 + 时间窗重叠」派生而来，是接触追踪的边。Ct = 接触发生时刻（重叠起点），
/// Tier = 空间接近度分层（同房/同区/同楼 → 风险等级）。同一次接触写**两个方向**（A→B 与 B→A），
/// 因为传染方向由时间决定而非空间——谁先感染谁就可能传给对方。
/// Derived from CTPresence via same-location + time-overlap. Ct = contact instant (overlap start),
/// Tier = spatial proximity tier. Each contact is stored in BOTH directions (A→B and B→A) because the
/// direction of transmission is decided by TIME, not space.
/// 
/// 传播链推理天生**多跳且时序递增**：从指示病例出发，沿 Ct 不减的接触链 k 跳内能波及谁？
/// 在 SQL 上就是对本表做 k 次自连接（PersonB→PersonA），且每跳加 Ct 单调约束——度^k 膨胀。
/// Transmission reasoning is inherently multi-hop AND time-respecting: k self-joins with a monotonic
/// Ct constraint, blowing up as degree^k.
/// Author: QP
/// Version: 1.0
/// Last Modified Date: 2026/08/11
Class EMR.Test.CTContact Extends %Persistent [ DdlAllowed ]
{

Property PersonA As %Integer;

Property PersonB As %Integer;

/// 接触发生时刻（时序链要求沿路 Ct 不减）/ contact instant; a transmission chain requires non-decreasing Ct.
Property Ct As %Integer;

Property LocId As %Integer;

/// 空间接近度分层 1=同房/高危 2=同区/中危 3=同楼/低危 / spatial proximity tier.
Property Tier As %Integer;

/// (PersonA, Ct) 复合索引：让每一跳的自连接（ON PersonA=… AND Ct>=…）走索引嵌套循环（对 SQL 有利）。
/// Composite index so each hop's self-join (ON PersonA=… AND Ct>=…) gets an index nested loop (favors SQL).
Index PACtIdx On (PersonA, Ct);

Storage Default
{
<Data name="CTContactDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>PersonA</Value>
</Value>
<Value name="3">
<Value>PersonB</Value>
</Value>
<Value name="4">
<Value>Ct</Value>
</Value>
<Value name="5">
<Value>LocId</Value>
</Value>
<Value name="6">
<Value>Tier</Value>
</Value>
</Data>
<DataLocation>^EMR.Test.CTContactD</DataLocation>
<DefaultData>CTContactDefaultData</DefaultData>
<IdLocation>^EMR.Test.CTContactD</IdLocation>
<IndexLocation>^EMR.Test.CTContactI</IndexLocation>
<StreamLocation>^EMR.Test.CTContactS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
