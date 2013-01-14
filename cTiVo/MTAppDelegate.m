//
//  MTAppDelegate.m
//  myTivo
//
//  Created by Scott Buchanan on 12/6/12.
//  Copyright (c) 2012 Scott Buchanan. All rights reserved.
//

#import "MTAppDelegate.h"
#import "MTTiVo.h"

void signalHandler(int signal)
{
	//Do nothing only use to intercept SIGPIPE.  Ignoring this should be fine as the the retry system should catch the failure and cancel and restart
	NSLog(@"Got signal %d",signal);
}

@implementation MTAppDelegate

- (void)dealloc
{
	[tiVoGlobalManager release];
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateTivoRefreshMenu) name:kMTNotificationTiVoListUpdated object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(getMediaKeyFromUser:) name:kMTNotificationMediaKeyNeeded object:nil];
	tiVoGlobalManager = [MTTiVoManager sharedTiVoManager];
	mainWindowController = nil;
	_formatEditorController = nil;
	[self showMainWindow:nil];
	[self updateTivoRefreshMenu];
	mediaKeyQueue = [NSMutableArray new];
	gettingMediaKey = NO;
	signal(SIGPIPE, &signalHandler);
	signal(SIGABRT, &signalHandler );
}

#pragma mark - UI support

-(void)updateTivoRefreshMenu
{
	if (tiVoGlobalManager.tiVoList.count == 0) {
		[refreshTiVoMenuItem setEnabled:NO];
	} else if (tiVoGlobalManager.tiVoList.count ==1) {
		[refreshTiVoMenuItem setTarget:nil];
		[refreshTiVoMenuItem setAction:NULL];
		if (((MTTiVo *)tiVoGlobalManager.tiVoList[0]).isReachable) {
			[refreshTiVoMenuItem setTarget:tiVoGlobalManager.tiVoList[0]];
			[refreshTiVoMenuItem setAction:@selector(updateShows:)];
			[refreshTiVoMenuItem setEnabled:YES];
		} else  {
			[refreshTiVoMenuItem setEnabled:NO];
		}
	} else {
		NSSortDescriptor *sd = [NSSortDescriptor sortDescriptorWithKey:@"tiVo.name" ascending:YES];
		NSArray *sortedTiVos = [[NSArray arrayWithArray:tiVoGlobalManager.tiVoList] sortedArrayUsingDescriptors:[NSArray arrayWithObject:sd]];
		NSMenu *thisMenu = [[[NSMenu alloc] initWithTitle:@"Refresh Tivo"] autorelease];
		for (MTTiVo *tiVo in sortedTiVos) {
			NSMenuItem *thisMenuItem = [[[NSMenuItem alloc] initWithTitle:tiVo.tiVo.name action:NULL keyEquivalent:@""] autorelease];
			if (!tiVo.isReachable) {
				NSFont *thisFont = [NSFont systemFontOfSize:13];
				NSString *thisTitle = [NSString stringWithFormat:@"%@ offline",tiVo.tiVo.name];
				NSAttributedString *aTitle = [[[NSAttributedString alloc] initWithString:thisTitle attributes:[NSDictionary dictionaryWithObjectsAndKeys:[NSColor redColor], NSForegroundColorAttributeName, thisFont, NSFontAttributeName, nil]] autorelease];
				[thisMenuItem setAttributedTitle:aTitle];
			} else {
				[thisMenuItem setTarget:tiVo];
				[thisMenuItem setAction:@selector(updateShows:)];
				[thisMenuItem setEnabled:YES];
			}
			[thisMenu addItem:thisMenuItem];
		}
		NSMenuItem *thisMenuItem = [[[NSMenuItem alloc] initWithTitle:@"All TiVos" action:NULL keyEquivalent:@""] autorelease];
		[thisMenuItem setTarget:self];
		[thisMenuItem setAction:@selector(updateAllTiVos:)];
		[thisMenuItem setEnabled:YES];
		[thisMenu addItem:thisMenuItem];
		[refreshTiVoMenuItem setSubmenu:thisMenu];
		[refreshTiVoMenuItem setEnabled:YES];
	}
	return;
	
}

-(IBAction)editFormats:(id)sender
{
	[self.formatEditorController showWindow:nil];
}

-(IBAction)exportFormats:(id)sender
{
	NSArray *userFormats = [[NSUserDefaults standardUserDefaults] arrayForKey:@"formats"];
	NSSavePanel *mySavePanel = [[[NSSavePanel alloc] init] autorelease];
	[mySavePanel setTitle:@"Save User Formats"];
	[mySavePanel setAllowedFileTypes:[NSArray arrayWithObject:@"plist"]];
	
	NSInteger ret = [mySavePanel runModal];
	if (ret == NSFileHandlingPanelOKButton) {
		NSString *filenmae = mySavePanel.URL.path;
		[userFormats writeToFile:filenmae atomically:YES];
	}
}

-(IBAction)importFormats:(id)sender
{
	
	NSArray *newFormats = nil;
	NSOpenPanel *myOpenPanel = [[[NSOpenPanel alloc] init] autorelease];
	[myOpenPanel setTitle:@"Import User Formats"];
	[myOpenPanel setAllowedFileTypes:[NSArray arrayWithObject:@"plist"]];
	NSInteger ret = [myOpenPanel runModal];
	if (ret == NSFileHandlingPanelOKButton) {
		NSString *filename = myOpenPanel.URL.path;
		newFormats = [NSArray arrayWithContentsOfFile:filename];
		[tiVoGlobalManager addFormatsToList:newFormats];	
	}
	
}

-(MTFormatEditorController *)formatEditorController
{
	if (!_formatEditorController) {
		_formatEditorController = [[MTFormatEditorController alloc] initWithWindowNibName:@"MTFormatEditorController"];
	}
	return _formatEditorController;
}

-(void)updateAllTiVos:(id)sender
{
	for (MTTiVo *tiVo in tiVoGlobalManager.tiVoList) {
		[tiVo updateShows:sender];
	}
}

-(void)getMediaKeyFromUser:(NSNotification *)notification
{
	if (notification && notification.object) {  //If sent a new tiVo then add to queue to start
		[mediaKeyQueue addObject:notification.object];
	}
	if (gettingMediaKey || mediaKeyQueue.count == 0) {  //If we're in the middle of a get or nothing to get return
		return;
	}
	MTTiVo *tiVo = [mediaKeyQueue objectAtIndex:0]; //Pop off the first in the queue
	gettingMediaKey = YES;
	if ( tiVo.mediaKey.length == 0 && tiVoGlobalManager.tiVoList.count && tiVo != (MTTiVo *)[tiVoGlobalManager.tiVoList objectAtIndex:0]) {
		tiVo.mediaKey = ((MTTiVo *)[tiVoGlobalManager.tiVoList objectAtIndex:0]).mediaKey;
		[mediaKeyQueue removeObject:tiVo];
		NSLog(@"set key for tivo %@ to %@",tiVo.tiVo.name,tiVo.mediaKey);
		[tiVo updateShows:nil];
	}  else {
		NSString *message = [NSString stringWithFormat:@"Need Media Key for %@",tiVo.tiVo.name];
		if (!tiVo.mediaKeyIsGood && tiVo.mediaKey.length > 0) {
			message = [NSString stringWithFormat:@"Incorrect Media Key for %@",tiVo.tiVo.name];
		}
		NSAlert *keyAlert = [NSAlert alertWithMessageText:message defaultButton:@"New Key" alternateButton:nil otherButton:nil informativeTextWithFormat:@""];
		NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
		
		[input setStringValue:tiVo.mediaKey];
		[input autorelease];
		[keyAlert setAccessoryView:input];
		NSInteger button = [keyAlert runModal];
		if (button == NSAlertDefaultReturn) {
			[input validateEditing];
			NSLog(@"Got Media Key %@",input.stringValue);
			tiVo.mediaKey = input.stringValue;
			[mediaKeyQueue removeObject:tiVo];
			[tiVo updateShows:nil]; //Assume if needed and got a key we should reload
		}
	}
	gettingMediaKey = NO;
	[[NSUserDefaults standardUserDefaults] setObject:[tiVoGlobalManager currentMediaKeys] forKey:kMTMediaKeys];
	[self getMediaKeyFromUser:nil];//Process rest of queue
}


#pragma mark - Application Support

- (NSURL *)applicationFilesDirectory
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *appSupportURL = [[fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
    return [appSupportURL URLByAppendingPathComponent:@"com.cTiVo.cTivo"];
}

-(IBAction)closeMainWindow:(id)sender
{
    [mainWindowController close];
}

-(IBAction)showMainWindow:(id)sender
{
	if (!mainWindowController) {
		mainWindowController = [[MTMainWindowController alloc] initWithWindowNibName:@"MTMainWindowController"];
	}
	[mainWindowController showWindow:nil];
	
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    // Save changes in the application's user defaults before the application terminates.
    [[NSUserDefaults standardUserDefaults] synchronize];
	[mediaKeyQueue release];
    return NSTerminateNow;
}

@end
