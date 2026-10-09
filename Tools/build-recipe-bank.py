#!/usr/bin/env python3
"""Build an attributed, source-linked CookOut catalog from Open Recipes.

Input: CC BY 3.0 Open Recipes JSON-lines gzip, mirrored by Jake VanderPlas.
No descriptions, images, reviews, or publisher cooking instructions are bundled.
This is an ingredient-based editorial selection, not a nutritional assessment.
"""
import argparse, collections, datetime, gzip, hashlib, html, json, re, unicodedata
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

PUBLISHERS = {
    'www.bbcgoodfood.com': 'BBC Good Food', 'allrecipes.com': 'Allrecipes',
    'www.bbc.co.uk': 'BBC Food', 'www.jamieoliver.com': 'Jamie Oliver',
    'www.101cookbooks.com': '101 Cookbooks', 'cookieandkate.com': 'Cookie and Kate',
    'naturallyella.com': 'Naturally Ella', 'www.cookincanuck.com': 'Cookin Canuck',
    'smittenkitchen.com': 'Smitten Kitchen', 'whatsgabycooking.com': "What's Gaby Cooking",
    'www.williams-sonoma.com': 'Williams Sonoma', 'www.bonappetit.com': 'Bon Appétit',
    'www.seriouseats.com': 'Serious Eats', 'www.aspicyperspective.com': 'A Spicy Perspective',
}
VEGETABLES = ['spinach','kale','broccoli','carrot','cabbage','tomato','zucchini','courgette','aubergine','eggplant','squash','pumpkin','sweet potato','beet','asparagus','cauliflower','bell pepper','peas','green beans','mushroom','lettuce','cucumber','chard','bok choy','brussels sprout','fennel','leek','artichoke','okra']
FRUITS = ['apple','pear','banana','blueberr','strawberr','raspberr','blackberr','peach','plum','apricot','mango','pineapple','orange','grape','melon','kiwi','cherr','pomegranate','avocado']
WHOLE_GRAINS = ['brown rice','wild rice','whole wheat','whole-wheat','wholemeal','whole grain','whole-grain','quinoa','bulgur','barley','farro','oats','oatmeal','buckwheat','millet','spelt']
LEGUMES = ['lentil','chickpea','garbanzo','black bean','kidney bean','white bean','cannellini','pinto bean','butter bean','edamame','tofu','tempeh','split pea']
PROTEIN = ['chicken','turkey','salmon','trout','sardine','tuna','cod','halibut','haddock','shrimp','prawn','egg','lean beef','pork tenderloin']
DAIRY = ['yogurt','yoghurt','milk','kefir','cottage cheese','ricotta']
NUTS = ['walnut','almond','peanut','cashew','pistachio','pecan','pumpkin seed','sunflower seed','sesame','chia','flax']
RESTRICTIVE = re.compile(r'\b(keto(?:genic)?|paleo|atkins|detox|fat[- ]?burn|weight[- ]?loss|low[- ]carb|zero[- ]carb)\b', re.I)
CUISINES = {'Italian':['italian','risotto','pesto','minestrone','caprese'], 'Mexican':['mexican','taco','enchilada','quesadilla','fajita'], 'Indian':['indian','dal','dhal','masala','biryani','tandoori'], 'Japanese':['japanese','miso','teriyaki','soba','sushi'], 'Chinese':['chinese','szechuan','sichuan','kung pao','chow mein'], 'Thai':['thai','pad thai'], 'Mediterranean':['mediterranean','greek','hummus','falafel','tabbouleh','tzatziki'], 'Middle Eastern':['middle eastern','lebanese','persian','tahini','harissa'], 'French':['french','ratatouille','nicoise'], 'American':['american','chowder','cornbread'], 'Korean':['korean','kimchi','bibimbap'], 'Vietnamese':['vietnamese','pho ','banh']}

def clean(s):
    return re.sub(r'\s+', ' ', html.unescape(s)).strip()

def folded(s):
    return ''.join(c for c in unicodedata.normalize('NFKD',s.lower()) if not unicodedata.combining(c))

def minutes(s):
    m=re.fullmatch(r'P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?',s or '')
    if not m:return None
    d,h,n,sec=(int(x or 0) for x in m.groups())
    value=d*1440+h*60+n+(1 if sec else 0)
    return value if 0<=value<=1440 else None

def category(title):
    t=title.lower()
    if re.search(r'\b(oatmeal|porridge|granola|breakfast|pancake|waffle|omelette|omelet|frittata|muesli)\b',t):return 'Breakfast'
    if re.search(r'\b(cake|cookies?|brownies?|dessert|crumble|cobbler|pudding|ice cream|tart)\b',t):return 'Dessert'
    if re.search(r'\b(smoothie|juice|drink|tea|coffee|lemonade)\b',t):return 'Drink'
    if re.search(r'\b(salad|soup|sandwich|wrap|lunch|chowder)\b',t):return 'Lunch'
    if re.search(r'\b(hummus|dip|snack|salsa|muffin|bread|scone|bar)\b',t):return 'Snack'
    return 'Dinner'

def matches(word,text):
    stem = word.endswith(('berr','cherr'))
    pattern = r'(?<![a-z])' + re.escape(word) + (r'[a-z]*' if stem else r'(?:s|es)?(?![a-z])')
    return re.search(pattern,text) is not None

def compile_catalog(source,output,target,link_status=None):
    statuses=json.loads(link_status.read_text()) if link_status else {}
    candidates=[];seen_urls=set();seen_content=set();raw_count=0
    with gzip.open(source,'rt',encoding='utf-8') as handle:
        for line in handle:
            raw_count+=1
            r=json.loads(line)
            title=clean(r.get('name',''))
            url=urlsplit(r.get('url',''))
            host=url.netloc.lower()
            if host not in PUBLISHERS or not title or len(title)>250 or RESTRICTIVE.search(title):continue
            if url.scheme not in ('http','https') or url.username or url.password:continue
            path=url.path.rstrip('/')
            if host=='www.bbcgoodfood.com':path=re.sub(r'^/recipes/\d+/', '/recipes/', path)
            if host=='cookieandkate.com':path=re.sub(r'^/\d{4}/', '/', path)
            if host in ['smittenkitchen.com']:path=path.replace('/blog/','/',1)
            if host=='www.aspicyperspective.com':path=re.sub(r'^/\d{4}/\d{2}/','/',path).removesuffix('.html')
            if host=='www.bonappetit.com' and path.startswith('/recipes/'):path='/recipe/'+path.split('/')[-1]
            if host=='www.jamieoliver.com':path=path.replace('-recipes/','/')
            if host=='www.seriouseats.com':path=re.sub(r'^/recipes/\d{4}/\d{2}/','/',path).removesuffix('.html')
            canonical=urlunsplit(('https',host,path,'',''))
            if canonical in seen_urls or statuses.get(canonical) in (404,410):continue
            ingredients=[]
            for text in r.get('ingredients','').splitlines():
                text=clean(text)
                # Keep ingredient facts; omit lengthy editorial explanations.
                # Preserve package sizes and ingredient alternatives in parentheses.
                text=clean(text)
                if 2<=len(text)<=200 and not re.match(r'^(?:for (?:the |a )?.+|ingredients(?: for .+)?)$',text,re.I) and not text.endswith(':'):ingredients.append(text)
            if not 3<=len(ingredients)<=35:continue
            low=folded(' '.join(ingredients));cat=category(title)
            groups=[]
            veg=sum(1 for word in VEGETABLES if matches(word,low))
            fruit=sum(1 for word in FRUITS if matches(word,low))
            whole=any(matches(word,low) for word in WHOLE_GRAINS)
            legumes=any(matches(word,low) for word in LEGUMES)
            protein=legumes or any(matches(word,low) for word in PROTEIN)
            dairy=any(matches(word, re.sub(r'\b(?:coconut|almond|oat|rice|soy|soya) milk\b','',low)) for word in DAIRY)
            nuts=any(matches(word,low) for word in NUTS)
            if veg:groups.append('Vegetables')
            if fruit:groups.append('Fruit')
            if whole:groups.append('Whole grains')
            if legumes:groups.append('Beans & lentils')
            if protein:groups.append('Protein foods')
            if dairy:groups.append('Dairy')
            if nuts:groups.append('Nuts & seeds')
            if not groups or not (veg or fruit or whole or legumes):continue
            if re.search(r'\b(deep[- ]fried|candy|fudge|cocktail|martini|vodka|liqueur)\b',title,re.I):continue
            prep=minutes(r.get('prepTime'));cook=minutes(r.get('cookTime'))
            total=(prep or 0)+(cook or 0) if prep is not None or cook is not None else None
            if total is not None and (total==0 or total>180):continue
            yield_text=clean(str(r.get('recipeYield','')))
            match=re.fullmatch(r'(?:serves?\s+(\d{1,2})|(\d{1,2})\s+servings?)',yield_text,re.I)
            servings=int(match.group(1) or match.group(2)) if match else None
            if servings is not None and not 1<=servings<=24:servings=None
            identity=folded(title)+'|'+ '|'.join(sorted(folded(x) for x in ingredients))
            if identity in seen_content:continue
            cuisines=[name for name,words in CUISINES.items() if any(w in folded(title+' '+str(r.get('description',''))) for w in words)]
            cuisine=cuisines[0] if cuisines else 'Global & everyday'
            score=veg*3+min(fruit,3)*2+whole*7+legumes*7+protein*3+nuts*2
            score-=sum(low.count(x)*2 for x in ['sugar','heavy cream','double cream','bacon','sausage','shortening'])
            if cat=='Dessert':score-=4
            if host in ['www.101cookbooks.com','cookieandkate.com','naturallyella.com']:score+=4
            if total and total<=45:score+=2
            if score<5:continue
            digest=hashlib.sha256(canonical.encode()).hexdigest()
            stable='-'.join([digest[:8],digest[8:12],'4'+digest[13:16],'8'+digest[17:20],digest[20:32]])
            record={'id':stable,'title':title,'ingredients':ingredients,'sourceURL':canonical,'publisher':PUBLISHERS[host],
                    'mealType':cat,'cuisine':cuisine,'foodGroups':groups,'prepMinutes':prep,'cookMinutes':cook,'totalMinutes':total,
                    'servings':servings,'selectionScore':score}
            candidates.append(record);seen_urls.add(canonical);seen_content.add(identity)
    candidates.sort(key=lambda r:(-r['selectionScore'],r['sourceURL']))
    # Retain useful meal and cuisine variety instead of filling the bank with
    # near-identical top-scoring salads. Every selected entry remains distinct.
    by_type=collections.defaultdict(list)
    for r in candidates:by_type[r['mealType']].append(r)
    quotas={'Breakfast':600,'Lunch':1800,'Dinner':3300,'Snack':550,'Dessert':200,'Drink':50}
    selected=[];selected_ids=set();publisher_counts=collections.Counter()
    def add(r):
        if r['id'] in selected_ids:return
        selected.append(r);selected_ids.add(r['id']);publisher_counts[r['publisher']]+=1
    for cat,quota in quotas.items():
        for r in by_type[cat][:quota]:add(r)
    for r in candidates:
        if len(selected)>=target:break
        add(r)
    selected=sorted(selected,key=lambda r:(-r['selectionScore'],r['title']))[:target]
    if len(selected)<5000:raise RuntimeError(f'Only {len(selected)} qualified records; do not pad the bank')
    document={'version':1,'catalogName':'CookOut Everyday Recipe Bank','compiledAt':'2026-10-08',
       'attribution':'Open Recipes Database © 2013 Fictive Kin LLC, CC BY 3.0. Data mirrored by Jake VanderPlas. Individual recipe publishers are credited on every record. CookOut selected, deduplicated, normalized, and annotated ingredient metadata. No cooking instructions, prose descriptions, or images are included.',
       'licenseURL':'https://creativecommons.org/licenses/by/3.0/',
       'datasetURL':'https://github.com/jakevdp/open-recipe-data',
       'nutritionGuidanceURL':'https://www.canada.ca/en/health-canada/services/food-guide/eating-support/cooking/make-healthy-meals-plate.html',
       'notes':'A historical, source-linked catalog. Links and yields can change. Food-group labels and selection are ingredient-based editorial heuristics, not measured nutrients or medical recommendations. Directions remain at each publisher. Recipes with unverified yields cannot be quantity-scaled.',
       'recipes':selected}
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(document,ensure_ascii=False,separators=(',',':'))+'\n')
    summary={'rawRecords':raw_count,'qualifiedRecords':len(candidates),'qualifiedPublishers':dict(collections.Counter(r['publisher'] for r in candidates)),'selectedRecords':len(selected),
       'uniqueSourceURLs':len({r['sourceURL'] for r in selected}),
       'mealTypes':dict(collections.Counter(r['mealType'] for r in selected)),
       'publishers':dict(collections.Counter(r['publisher'] for r in selected)),
       'foodGroups':dict(collections.Counter(g for r in selected for g in r['foodGroups'])),
       'cuisines':dict(collections.Counter(r['cuisine'] for r in selected)),
       'linkChecks':dict(collections.Counter(statuses.get(r['sourceURL'], 'unchecked') for r in selected)),
       'knownServings':sum(r['servings'] is not None for r in selected),
       'sourceSHA256':hashlib.sha256(source.read_bytes()).hexdigest(),
       'catalogSHA256':hashlib.sha256(output.read_bytes()).hexdigest()}
    output.with_name('recipe-bank-provenance.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps(summary,indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('source',type=Path);parser.add_argument('--output',type=Path,default=Path('CookOut/Resources/recipe-bank.json'));parser.add_argument('--count',type=int,default=6500)
    parser.add_argument('--link-status',type=Path,default=Path(__file__).with_name('recipe-link-checks.json'))
    args=parser.parse_args();compile_catalog(args.source,args.output,args.count,args.link_status)
