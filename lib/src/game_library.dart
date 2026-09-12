// Game Boost - built-in library of popular mobile games and the process name
// patterns that commonly identify them on Android.
//
// NOTE: game developers rename binaries between updates. The pattern list is
// deliberately broad (matched case-insensitively against the executable name
// and full command line). If a title is not detected, tap "Detected apps" to
// add it from the list of processes that are actually running on the device.

class KnownGame {
  const KnownGame(this.name, this.patterns);
  final String name;
  final List<String> patterns;
}

const List<KnownGame> KNOWN_GAMES = const [
  const KnownGame('Battlegrounds Mobile India (BGMI)', const ['pubg.imobile', 'bgmi', 'battlegrounds', 'krafton']),
  const KnownGame('Free Fire / Free Fire MAX', const ['dts.freefireth', 'dts.freefiremax', 'freefire', 'ffes']),
  const KnownGame('PUBG Mobile', const ['tencent.ig', 'pubg', 'pubgm', 'vng.pubgmobile']),
  const KnownGame('Call of Duty Mobile', const ['activision.callofduty.shooter', 'cod_m', 'callofduty', 'call_of_duty', 'codm']),
  const KnownGame('Call of Duty: Warzone Mobile', const ['activision.callofduty.warzone', 'warzone', 'warzonemobile']),
  const KnownGame('Genshin Impact', const ['mihoyo.genshinimpact', 'genshin']),
  const KnownGame('Honkai: Star Rail', const ['honkaistarrail', 'starrail', 'hkrpg']),
  const KnownGame('Zenless Zone Zero', const ['zenless', 'zzz', 'nap']),
  const KnownGame('Mobile Legends: Bang Bang', const ['mobile.legends', 'mobilelegends', 'mlbb', 'moonton']),
  const KnownGame('PUBG: New State', const ['newstate', 'pubg_new_state']),
  const KnownGame('Clash Royale', const ['clashroyale']),
  const KnownGame('Clash of Clans', const ['clashofclans', 'clash_of_clans']),
  const KnownGame('Brawl Stars', const ['brawlstars', 'brawl_stars']),
  const KnownGame('Candy Crush Saga', const ['candycrush', 'candy_crush']),
  const KnownGame('Subway Surfers', const ['subwaysurfers', 'subway_surfers']),
  const KnownGame('Temple Run 2', const ['templerun', 'temple_run']),
  const KnownGame('Angry Birds', const ['angrybirds', 'angry_birds']),
  const KnownGame('Minecraft Pocket', const ['minecraft', 'mcpel', 'bedrock']),
  const KnownGame('Roblox', const ['roblox']),
  const KnownGame('Fortnite', const ['fortnite', 'fnite', 'fneac']),
  const KnownGame('eFootball', const ['efootball', 'pes']),
  const KnownGame('FIFA/Fc Mobile', const ['fifamobile', 'ea.aa.fifa', 'fc_mobile', 'eafc']),
  const KnownGame('Racing Masters', const ['racingmasters', 'racing_masters']),
  const KnownGame('Asphalt 9', const ['asphalt9', 'asphalt_9']),
  const KnownGame('Need for Speed', const ['needforspeed', 'nfs']),
  const KnownGame('Tomb Raider Reloaded', const ['tombraider', 'tomb_raider']),
  const KnownGame('Assassin\'s Creed Codename Jade', const ['assassinscreed', 'acjade']),
  const KnownGame('FC Tactical', const ['fctactical', 'fc_tactical']),
  const KnownGame('Marvel Snap', const ['marvelsnap', 'marvel_snap']),
  const KnownGame('Marvel Contest of Champions', const ['contestofchampions', 'mcoc']),
  const KnownGame('Pokemon Unite', const ['pokemonunite', 'pokemon_unite']),
  const KnownGame('Pokemon GO', const ['pokemongo', 'pokemon_go', 'pokemongodev']),
  const KnownGame('Hawked', const ['hawked']),
  const KnownGame('Critical Ops', const ['criticalops', 'critical_ops']),
  const KnownGame('World of Tanks Blitz', const ['wotblitz', 'tanksblitz']),
  const KnownGame('War Robots', const ['warrobots', 'war_robots']),
  const KnownGame('Standoff 2', const ['standoff2', 'standoff_2']),
  const KnownGame('Metal Slug', const ['metalslug', 'metal_slug']),
  const KnownGame('Street Fighter: Duel', const ['sfinchallenge', 'streetfighter', 'street_fighter']),
  const KnownGame('Yu-Gi-Oh! Master Duel', const ['masterduel', 'master_duel', 'yugioh']),
  const KnownGame('Chess', const ['chess']),
  const KnownGame('8 Ball Pool', const ['8ball', 'eightball']),
  const KnownGame('Mafia', const ['mafiacity', 'mafia']),
  const KnownGame('The Walking Dead', const ['thewalkingdead', 'twd']),
  const KnownGame('Final Fantasy', const ['finalfantasy', 'final_fantasy', 'ffbe', 'ff7', 'ffvii', 'ffxiv']),
  const KnownGame('Diablo Immortal', const ['diablo', 'diabloimmortal']),
  const KnownGame('Elder Scrolls: Blades', const ['escrolls', 'blades', 'elderscrolls']),
  const KnownGame('Apex Legends Mobile', const ['apex']),
  const KnownGame('Overwatch', const ['overwatch']),
  const KnownGame('Fruit Ninja', const ['fruitninja', 'fruit_ninja']),
  const KnownGame('Jetpack Joyride', const ['jetpackjoyride', 'jetpack_joyride']),
];