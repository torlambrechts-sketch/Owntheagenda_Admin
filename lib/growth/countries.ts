/**
 * A country as Search Console names it (ISO 3166-1 alpha-3, lower case: «nor») to the name a reader of this locale knows
 * it by (0090). Intl.DisplayNames names regions by their alpha-2 code, so the alpha-3 codes are mapped first; the table is
 * ISO 3166-1 as the iso-codes project publishes it, and Kosovo. «zzz», Google's «could not tell», and any code not in the table have
 * no name: the caller shows its own word for unknown.
 */
// alpha-3 then alpha-2, five letters a country
const TABLE =
  "abwAW afgAF agoAO aiaAI alaAX albAL andAD areAE argAR armAM asmAS ataAQ atfTF atgAG ausAU autAT azeAZ bdiBI belBE " +
  "benBJ besBQ bfaBF bgdBD bgrBG bhrBH bhsBS bihBA blmBL blrBY blzBZ bmuBM bolBO braBR brbBB brnBN btnBT bvtBV bwaBW " +
  "cafCF canCA cckCC cheCH chlCL chnCN civCI cmrCM codCD cogCG cokCK colCO comKM cpvCV criCR cubCU cuwCW cxrCX cymKY " +
  "cypCY czeCZ deuDE djiDJ dmaDM dnkDK domDO dzaDZ ecuEC egyEG eriER eshEH espES estEE ethET finFI fjiFJ flkFK fraFR " +
  "froFO fsmFM gabGA gbrGB geoGE ggyGG ghaGH gibGI ginGN glpGP gmbGM gnbGW gnqGQ grcGR grdGD grlGL gtmGT gufGF gumGU " +
  "guyGY hkgHK hmdHM hndHN hrvHR htiHT hunHU idnID imnIM indIN iotIO irlIE irnIR irqIQ islIS isrIL itaIT jamJM jeyJE " +
  "jorJO jpnJP kazKZ kenKE kgzKG khmKH kirKI knaKN korKR kwtKW laoLA lbnLB lbrLR lbyLY lcaLC lieLI lkaLK lsoLS ltuLT " +
  "luxLU lvaLV macMO mafMF marMA mcoMC mdaMD mdgMG mdvMV mexMX mhlMH mkdMK mliML mltMT mmrMM mneME mngMN mnpMP mozMZ " +
  "mrtMR msrMS mtqMQ musMU mwiMW mysMY mytYT namNA nclNC nerNE nfkNF ngaNG nicNI niuNU nldNL norNO nplNP nruNR nzlNZ " +
  "omnOM pakPK panPA pcnPN perPE phlPH plwPW pngPG polPL priPR prkKP prtPT pryPY psePS pyfPF qatQA reuRE rouRO rusRU " +
  "rwaRW sauSA sdnSD senSN sgpSG sgsGS shnSH sjmSJ slbSB sleSL slvSV smrSM somSO spmPM srbRS ssdSS stpST surSR svkSK " +
  "svnSI sweSE swzSZ sxmSX sycSC syrSY tcaTC tcdTD tgoTG thaTH tjkTJ tklTK tkmTM tlsTL tonTO ttoTT tunTN turTR tuvTV " +
  "twnTW tzaTZ ugaUG ukrUA umiUM uryUY usaUS uzbUZ vatVA vctVC venVE vgbVG virVI vnmVN vutVU wlfWF wsmWS yemYE zafZA " +
  "zmbZM zweZW " +
  // Kosovo: not in ISO 3166-1, but Google writes it «xkk» and Intl names it by «XK»
  "xkkXK"

const ALPHA2: ReadonlyMap<string, string> = new Map(TABLE.split(' ').map((c) => [c.slice(0, 3), c.slice(3)] as const))

/** the country's name in this locale, or null when Google could not tell or the code is not a country */
export function countryName(alpha3: string, locale: string): string | null {
  const a2 = ALPHA2.get(alpha3.toLowerCase())
  if (!a2) return null
  try {
    return new Intl.DisplayNames([locale === 'no' ? 'nb' : locale], { type: 'region' }).of(a2) ?? null
  } catch {
    return null
  }
}
