// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <XCTest/XCTest.h>
#import "FIAPRequestHandler.h"
#import "Stubs.h"

#pragma tests start here

@interface RequestHandlerTest : XCTestCase

@end

@implementation RequestHandlerTest

- (void)testRequestHandlerWithProductRequestSuccess {
  SKProductRequestStub *request =
      [[SKProductRequestStub alloc] initWithProductIdentifiers:[NSSet setWithArray:@[ @"123" ]]];
  FIAPRequestHandler *handler = [[FIAPRequestHandler alloc] initWithRequest:request];
  XCTestExpectation *expectation =
      [self expectationWithDescription:@"expect to get response with 1 product"];
  __block SKProductsResponse *response;
  [handler
      startProductRequestWithCompletionHandler:^(SKProductsResponse *_Nullable r, NSError *error) {
        response = r;
        [expectation fulfill];
      }];
  [self waitForExpectations:@[ expectation ] timeout:5];
  XCTAssertNotNil(response);
  XCTAssertEqual(response.products.count, 1);
  SKProduct *product = response.products.firstObject;
  XCTAssertTrue([product.productIdentifier isEqualToString:@"123"]);
}

- (void)testRequestHandlerWithProductRequestFailure {
  SKProductRequestStub *request = [[SKProductRequestStub alloc]
      initWithFailureError:[NSError errorWithDomain:@"test" code:123 userInfo:@{}]];
  FIAPRequestHandler *handler = [[FIAPRequestHandler alloc] initWithRequest:request];
  XCTestExpectation *expectation =
      [self expectationWithDescription:@"expect to get response with 1 product"];
  __block NSError *error;
  __block SKProductsResponse *response;
  [handler startProductRequestWithCompletionHandler:^(SKProductsResponse *_Nullable r, NSError *e) {
    error = e;
    response = r;
    [expectation fulfill];
  }];
  [self waitForExpectations:@[ expectation ] timeout:5];
  XCTAssertNotNil(error);
  XCTAssertEqual(error.domain, @"test");
  XCTAssertNil(response);
}

@end
