# GovPulse AI Accuracy Test – Instructions for Claude Code

Run this whole task on your own from start to finish. Do not stop to ask me for approval. Make reasonable decisions and write every decision and problem in the final report.

## Goal

My thesis measures how accurate GovPulse's AI is. Two human raters answered a rating form with 36 items (12 reports, 12 suggestions, 12 feedback). I need GovPulse to answer the SAME 36 items so I can compare the system's answers to the raters' answers (precision, recall, F1).

Your job: run the 36 items below through the REAL GovPulse pipeline and give me a simple report of what GovPulse answered.

## Rules (very important)

1. Every label must come from GovPulse itself (its Supabase edge functions, its prompts, its Groq model). Do NOT classify anything yourself, do NOT guess, do NOT use any other model. If GovPulse gives no answer for an item, write "NO OUTPUT" and explain why. A blank is better than an invented answer.
2. Do NOT change any edge function, prompt, model, temperature, rule, trigger, or migration. I am testing the system as it is.
3. Do NOT edit or delete any record you did not create. Tag every record you create so it can be found and cleaned up later (for example put "TEST-EVAL" in a field that does not affect classification, or keep a list of the created IDs).
4. Use the credentials in .env (SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, TEST_USER_EMAIL). Never print the keys.
5. Copy the 36 texts EXACTLY as written below, including punctuation. Do not translate, fix spelling, or shorten them.
6. Before claiming anything about how the system works, verify it by reading the actual code. In the report, cite the file and function you read.

## Step 1 – Verify how the system works (read the code first)

Read supabase/functions and supabase/migrations and find out, for reports, suggestions, and feedback:
- Which table the submission goes into and which trigger classifies it.
- Which edge function and which model does the classification.
- Where the results are saved (which columns), and how the system records whether a label came from the AI or from the rule-based fallback.
- Whether the system actually outputs each label I need: report category, report urgency, suggestion category (the "Looks like" suggestion), feedback sentiment, feedback urgency. If the system does NOT produce one of these (for example, if report category is only what the citizen picks), say so clearly and do not fake it.
- Which input fields the classifier reads besides the text (for example the category the citizen picked, the star rating, the barangay, how many similar reports exist). These can change the answer, so check them.

## Step 2 – Insert the 36 items as test records

Insert each item as a new record under the test account so the database triggers classify it exactly as they would for a real citizen.

For required fields that are not the text:
- Pick the most neutral value possible so it does not push the AI toward an answer. For example, if the citizen must pick a category, use "Others" if it exists. If feedback needs a star rating and the classifier reads it, use the middle value (3).
- Use the same neutral values for every item.
- List every value you used in the report.

If urgency counts "similar reports" from recent submissions, check whether inserting all 12 reports together would raise each other's urgency. If it would, prevent that (for example, insert them far enough apart or in a way they are not counted together) and explain what you did.

Wait until every item is classified, including any scheduled catch-up job. If an item stays unclassified after a reasonable wait, mark it "NO OUTPUT".

## Step 3 – Collect the answers

Read the saved labels back from the database. Do not use any other source.

The raters chose from these exact options, so map GovPulse's answers to them. If GovPulse uses a different name, show both the raw value and the mapped value. If there is no clear match, write the raw value and mark it "UNMAPPED". Do not guess.

- Report category: Road & Infrastructure, Waste & Garbage, Drainage & Flooding, Streetlight Outage, Environment & Pollution, Others
- Suggestion category: Public Service, Community Program, Health & Safety, Infrastructure, Environment & Cleanliness, Others
- Sentiment: Positive, Neutral, Negative
- Urgency: High, Medium, Low

## The 36 items (copy exactly)

### Form A – Reports (GovPulse should give: category + urgency)
R1 | Gumuho na ang gilid ng kalsada malapit sa tulay. Muntik nang mahulog ang isang tricycle kagabi.
R2 | Adda dakkel nga abut iti kalsada iti sango ti eskuelaan. Adu dagiti ubbing a lumasat ditoy.
R3 | URGENT!!! The paint of the pedestrian lane in front of the school is already faded!!!
R4 | Saan a naala ti basura mi iti las-ud ti maysa a lawas. Nabangsit unayen.
R5 | The garbage bin beside the waiting shed is already full. Please have it emptied when the truck passes.
R6 | Baha na sa loob ng mga bahay namin, hanggang tuhod na ang tubig. May mga bata at senior dito, please help ASAP.
R7 | The canal along our street is clogged with plastic. When it rains, water stays on the road for hours.
R8 | Tatlong poste ng ilaw ang patay sa kalye namin. Madilim at delikado sa gabi, lalo na sa mga estudyante.
R9 | Saan nga agsilsilaw ti maysa a poste iti igid ti plasa.
R10 | Someone burns plastic and rubber behind the market every night. The smoke goes straight into our houses.
R11 | Sobrang lakas ng videoke ng kapitbahay hanggang 2am, every weekend na po.
R12 | A stray dog has been sleeping at the entrance of the barangay hall for a few days now.

### Form B – Suggestions (GovPulse should give: category)
S1 | Please allow online payment for business permit renewal so residents do not have to line up.
S2 | Sana may hiwalay na pila para sa mga senior citizen at PWD sa Treasurer's Office.
S3 | Sapay koma ta adda libre a seminar iti panagnegosio para kadagiti babbai iti barangay mi.
S4 | Sana po magkaroon ng basketball league para sa youth this summer, para iwas bisyo.
S5 | Sapay koma ta adda libre a medical mission para kadagiti lallakay ken babbaket iti barangay mi.
S6 | Please assign tanods at the plaza at night. There have been several snatching incidents.
S7 | Sana po lagyan ng waiting shed ang sakayan sa national highway. Wala kaming masilungan kapag umuulan.
S8 | Paki-install po ng streetlights sa road going to the beach, super dilim and maraming students ang dumadaan.
S9 | Mabalin koma nga agmula kami iti kayo iti igid ti karayan tapno saan nga agregreg ti daga.
S10 | Put up separate bins for biodegradable and non-biodegradable waste in every purok.
S11 | Please name the new park after a local hero of Aparri.
S12 | Sapay koma ta adda museo ti Aparri a pakakitaan ti pakasaritaan ti ili.

### Form C – Feedback (GovPulse should give: sentiment + urgency)
F1 | Very accommodating staff. I got my business permit in less than an hour. Thank you!
F2 | Napintas ti serbisio. Napardas ken nasayaat ti panangtrato dagiti empleado. Agyamanak.
F3 | Mabilis ang pagkuha ng birth certificate ko. Malaking pagbabago kumpara noon.
F4 | Super bait ni ate sa window, she explained everything clearly. Salamat po!
F5 | I requested a copy of my marriage certificate this morning. I was told to come back on Friday.
F6 | Nagpabakuna ako ng anti-rabies sa Health Office kahapon.
F7 | Nagala ak iti Mayor's clearance idi Martes.
F8 | Tatlong oras akong naghintay para sa kopya ng birth certificate. Isang window lang ang bukas.
F9 | Nabayag ti panagur-ay mi, dua nga oras sakbay a naserbian. Awan pay ti sumungbat kadagiti saludsod mi.
F10 | Mabilis naman ang process, pero ang sungit ng staff sa window. Parang galit pa sa amin.
F11 | Ang galing talaga, pinabalik-balik ako ng limang beses para lang sa isang pirma.
F12 | The Health Office sent my father home without an anti-rabies shot after a dog bite because they had no vaccine. We had to go to the city.

## Step 4 – Output

Create two files in the project folder:

**1. govpulse_results.csv** with one row per item:
item_id, type, text, system_category, system_category_raw, system_urgency, system_sentiment, label_source (AI or fallback), model, record_id, classified_at

**2. GOVPULSE_RESULTS.md**, a SIMPLE report in plain language:
- A short "How the test was run" section: what was inserted, which functions and model classified it, the neutral values used, and anything that went wrong.
- Three simple tables (Reports, Suggestions, Feedback) showing item ID, a short start of the text, and GovPulse's answer.
- A list of any item labeled by the fallback instead of the AI, any "NO OUTPUT", and any "UNMAPPED".
- The exact command or script to delete all the TEST-EVAL records later. Do NOT run the deletion yourself.

Do not calculate accuracy or F1. I will compare these results with my raters' answers separately.
