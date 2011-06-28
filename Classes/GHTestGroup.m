//
//  GHTestGroup.m
//
//  Created by Gabriel Handford on 1/16/09.
//  Copyright 2009. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//

//
// Portions of this file fall under the following license, marked with:
// GTM_BEGIN : GTM_END
//
//  Copyright 2008 Google Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not
//  use this file except in compliance with the License.  You may obtain a copy
//  of the License at
// 
//  http://www.apache.org/licenses/LICENSE-2.0
// 
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
//  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
//  License for the specific language governing permissions and limitations under
//  the License.
//

#import "GHTestGroup.h"
#import "GHTestCase.h"

#import "GHTesting.h"
#import "GTMStackTrace.h"

@interface GHTestGroup (Private)
- (void)_addTest:(id<GHTest>)test;
- (void)_addTestsFromTestCase:(id)testCase;
@end

@implementation GHTestGroup

@synthesize stats=stats_, parent=parent_, children=children_, delegate=delegate_, interval=interval_, 
status=status_, testCase=testCase_, exception=exception_;

- (id)initWithName:(NSString *)name delegate:(id<GHTestDelegate>)delegate {
	if ((self = [super init])) {
		name_ = [name retain];				
		children_ = [[NSMutableArray array] retain];
		delegate_ = delegate;
	} 
	return self;
}

- (id)initWithTestCase:(id)testCase delegate:(id<GHTestDelegate>)delegate {
	if ([self initWithName:NSStringFromClass([testCase class]) delegate:delegate]) {
		testCase_ = [testCase retain];
		[self _addTestsFromTestCase:testCase];
	}
	return self;
}

- (id)initWithTestCase:(id)testCase selector:(SEL)selector delegate:(id<GHTestDelegate>)delegate {
	if ([self initWithName:NSStringFromClass([testCase class]) delegate:delegate]) {
		testCase_ = [testCase retain];
		[self _addTest:[GHTest testWithTarget:testCase selector:selector]];
	}
	return self;
}

+ (GHTestGroup *)testGroupFromTestCase:(id)testCase delegate:(id<GHTestDelegate>)delegate {
	return [[[GHTestGroup alloc] initWithTestCase:testCase delegate:delegate] autorelease];
}

- (void)dealloc {
	for(id<GHTest> test in children_)
		[test setDelegate:nil];
	[name_ release];
	[children_ release];
	[testCase_ release];
	delegate_ = nil;
	[super dealloc];
}

- (NSString *)description {
	return [NSString stringWithFormat:@"%@, %d %0.3f %d/%d (%d failures)", 
								 name_, status_, interval_, stats_.succeedCount, stats_.testCount, stats_.failureCount];
}
	
- (NSString *)name {
	return name_;
}

- (void)_addTestsFromTestCase:(id)testCase {
	NSArray *tests = [[GHTesting sharedInstance] loadTestsFromTarget:testCase];
	for(GHTest *test in tests) {
		[self _addTest:test];
	}
}

- (void)addTestCase:(id)testCase {
	GHTestGroup *testCaseGroup = [[GHTestGroup alloc] initWithTestCase:testCase delegate:self];
	[self addTestGroup:testCaseGroup];
	[testCaseGroup release];
}

- (void)addTestGroup:(GHTestGroup *)testGroup {
	[self _addTest:testGroup];
	[testGroup setParent:self];		
}

- (void)_addTest:(id<GHTest>)test {
	[test setDelegate:self];	
	stats_.testCount += [test stats].testCount;
	[children_ addObject:test];	
}

- (NSString *)identifier {
	return name_;
}

// Forward up
- (void)test:(id<GHTest>)test didLog:(NSString *)message source:(id<GHTest>)source {
	[delegate_ test:self didLog:message source:source];	
}

- (NSArray *)log {
	// Not supported for group (though may be an aggregate of child test logs in the future?)
	return nil;
}

- (void)reset {
	status_ = GHTestStatusNone;
	stats_ = GHTestStatsMake(0, 0, 0, stats_.testCount);
	interval_ = 0;
	[exception_ release];
	exception_ = nil;
	for(id<GHTest> test in children_) {
		[test reset];		
	}
	[delegate_ testDidUpdate:self source:self];
}

- (void)setException:(NSException *)exception {
	[exception retain];
	[exception_ release];
	exception_ = exception;
	status_ = GHTestStatusErrored;
	[delegate_ testDidUpdate:self source:self];
}

- (void)cancel {
	if (status_ == GHTestStatusRunning) {
		status_ = GHTestStatusCancelling;
	} else {
		for(id<GHTest> test in children_) {
			stats_.cancelCount++;
			[test cancel];
		}
		status_ = GHTestStatusCancelled;
	}
	[delegate_ testDidUpdate:self source:self];
}

- (void)setDisabled:(BOOL)disabled {
	[self reset];
	[delegate_ testDidUpdate:self source:self];
}

- (BOOL)isDisabled {
	for(id<GHTest> test in children_)
		if (![test isDisabled]) return NO;
	return YES;
}

- (NSInteger)disabledCount {
	NSInteger disabledCount = 0;
	for(id<GHTest> test in children_) {
		disabledCount += [test disabledCount];
	}
	return disabledCount;
}

- (void)_checkSetUpClass {
	if (didSetUpClass_) return;
	didSetUpClass_ = YES;
	// Set up class (if we have a test case)
	@try {		
		if ([testCase_ respondsToSelector:@selector(setUpClass)])			
			[testCase_ setUpClass];
	} @catch(NSException *exception) {
		// If we fail in the setUpClass, then we will cancel all the child tests (below)
		exception_ = [exception retain];
		status_ = GHTestStatusErrored;
		for(id<GHTest> test in children_) {
			if (![test isDisabled]) {
				stats_.failureCount++;
				[test setException:exception_];
			}
		}
	}
}

- (void)_tearDownClass {
	// Tear down class (if we have a test case)
	if (status_ == GHTestStatusRunning) {
		@try {
			if ([testCase_ respondsToSelector:@selector(tearDownClass)])		
				[testCase_ tearDownClass];
		} @catch(NSException *exception) {					
			exception_ = [exception retain];
			status_ = GHTestStatusErrored;
			// We need to reverse any successes in the test run above
			// and set the error on all the child tests
			for(id<GHTest> test in children_) {				
				if ([test status] == GHTestStatusSucceeded) {
					stats_.succeedCount--;
					stats_.failureCount++;
				}
				if (![test isDisabled])
					[test setException:exception_];
			}
		}
	}
}

- (void)_run:(NSOperationQueue *)operationQueue {
	if (status_ == GHTestStatusCancelled || (([children_ count] - [self disabledCount]) <= 0)) {
		return;
	}

	didSetUpClass_ = NO;
	status_ = GHTestStatusRunning;	
	[delegate_ testDidStart:self source:self];
	
	// Run the tests
	for(id<GHTest> test in children_) {
		// If we are cancelling mark all child tests cancelled (and update stats)
		// If we errored (above), then set the error on the test (and update stats)
		// Otherwise run it
		if (status_ == GHTestStatusCancelling) {
			stats_.cancelCount++;
			[test cancel];
		} else if (status_ == GHTestStatusErrored) {
			stats_.failureCount++;
			[test setException:exception_];
		} else {				
			if (operationQueue) {
				[operationQueue addOperation:[[[GHTestOperation alloc] initWithTest:test] autorelease]];
			} else {
				if (![test isDisabled]) {
					[self _checkSetUpClass];
				}
				if (status_ == GHTestStatusErrored) break;
				[test run];
			}
		}
	}
	[operationQueue waitUntilAllOperationsAreFinished];
	
	// Tear down class only if we set up class
	if (didSetUpClass_) 
		[self _tearDownClass];
	
	if (status_ == GHTestStatusCancelling) {
		status_ = GHTestStatusCancelled;
	} else if (exception_ || stats_.failureCount > 0) {
		status_ = GHTestStatusErrored;
	} else {
		status_ = GHTestStatusSucceeded;
	}	
	[delegate_ testDidEnd:self source:self];
}

- (void)runInOperationQueue:(NSOperationQueue *)operationQueue {
	[self _run:operationQueue];
}

- (BOOL)shouldRunOnMainThread {
	if ([testCase_ respondsToSelector:@selector(shouldRunOnMainThread)]) 
		return [testCase_ shouldRunOnMainThread];
	return NO;
}

- (void)run {	
	if ([self shouldRunOnMainThread]) {
		[self performSelectorOnMainThread:@selector(_run:) withObject:nil waitUntilDone:YES];
	} else {
		[self _run:nil];
	}	
}

#pragma mark Delegates (GHTestDelegate)

- (void)testDidStart:(id<GHTest>)test source:(id<GHTest>)source {
	[delegate_ testDidStart:self source:source];
	[delegate_ testDidUpdate:self source:self];	
}

- (void)testDidUpdate:(id<GHTest>)test source:(id<GHTest>)source {
	[delegate_ testDidUpdate:self source:source];	
	[delegate_ testDidUpdate:self source:self];	
}

- (void)testDidEnd:(id<GHTest>)test source:(id<GHTest>)source {	
	if (source == test) {
		if ([test interval] >= 0)
			interval_ += [test interval];	
		stats_.failureCount += [test stats].failureCount;
		stats_.succeedCount += [test stats].succeedCount;
		stats_.cancelCount += [test stats].cancelCount;		
	}
	[delegate_ testDidEnd:self source:source];
	[delegate_ testDidUpdate:self source:self];	
}

@end
