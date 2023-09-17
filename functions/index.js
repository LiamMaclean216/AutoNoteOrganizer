/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const { onRequest } = require('firebase-functions/v2/https');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');
const { ChatOpenAI } = require('langchain/chat_models/openai');
const { HumanMessage, SystemMessage } = require('langchain/schema');

admin.initializeApp();
const model = new ChatOpenAI({
	model: 'gpt-3.5-turbo-0613',
	temperature: 0,
	openAIApiKey: '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' // In Node.js defaults to process.env.OPENAI_API_KEY
});

function addNote(args) {
	admin.firestore().collection('notes').doc(args.title).set({ content: args.content });
	return {
		response: `Added note with title: ${args.title} and content: ${args.content}`,
		title: args.title,
		content: args.content,
		functionCall: true
	};
}

const available_functions = {
	addNote
};
exports.helloWorld = onRequest(
	{ timeoutSeconds: 15, cors: true, maxInstances: 10 },
	async (request, response) => {
		logger.info('Hello logs!' + JSON.stringify(request.body), { structuredData: true });

		const gptResponse = await model.predictMessages(
			[
				new SystemMessage(`
Initial User Prompt: "Take a note". Anticipate entries users wish to record.
Note Processing:
Generates a concise version of user input.
Categorizes the note. Example: "eggs" -> Category: "Grocery List", Content: "eggs".
Retains the full user input.
Reformats notes for clarity. E.g., "Egg, cereal milk" to:
eggs
cereal
milk
However, make sure the meaning of the note is not changed.
Corrects and refines entries: "Raed Halmet" becomes "Hamlet by William Shakespeare" under "Books to Read".
Ensure you provide clear and concise input for best categorization and reformatting.
The current existing categories are: "Philosophy", "Books to Read." New categories can be added. Categories should usually be plural.
Categories should be broad, for example "Leak 120$ to fix" should go under "Expenses".
Random objects that can be bough should go under "Shopping List", for example "Bathroom Scale". Note that this is different from Groceries, so "Chicken Break" would always go under "Groceries" instead of "Shopping List".

Anticipate what the user intends to do with the note, for example "game: Fortnite" should be noted under "Games to Play".

The user is not addressing the assistant, they want to take a note. The assistant should not respond to this prompt, unless to ask for clarification.

Users note format may include the note and what category it should be under. For example "Barrie show" -> Category: "Shows to watch", Content: "Barrie". Do not include category in the content.

For example, "pretend to holding beer while presenting for natural hand movement" should be noted under "Presentation Tips"
`),
				new HumanMessage(`Existing categories are:${request.body['data']['existingTitles']}
			
User input: ${request.body['data']['prompt']}`)
			],
			{
				functions: [
					{
						name: 'addNote',
						description: 'Use this whenever a user wants to add a note',
						parameters: {
							type: 'object',
							properties: {
								content: {
									type: 'string',
									description:
										'The users note content, transformed to be more human readable and brief. One sentence at the very maximum. Fix the users spelling and grammar.'
								},
								title: {
									type: 'string',
									description:
										'The category of the note. For example, "eggs" would have a title of "Shopping List". A few words at most, and a broad category.'
								}
							},
							required: ['content', 'title']
						}
					}
				]
			}
		);

		if (gptResponse.content) {
			response.send({data: { response: gptResponse.content, functionCall: false }});
			return;
		}

		const function_call = gptResponse.additional_kwargs.function_call;
		const func = available_functions[function_call.name];

		if (!func) {
			response.send('Error, function not found ' + JSON.stringify(gptResponse));
			return;
		}
		response.send({data: func(JSON.parse(function_call.arguments))});
	}
);
