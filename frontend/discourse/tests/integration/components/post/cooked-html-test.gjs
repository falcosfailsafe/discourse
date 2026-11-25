import { tracked } from "@glimmer/tracking";
import { getOwner } from "@ember/owner";
import { trackedMap } from "@ember/reactive/collections";
import { click, render, settled } from "@ember/test-helpers";
import { module, test } from "qunit";
import PostCookedHtml from "discourse/components/post/cooked-html";
import PostQuotedContent from "discourse/components/post/quoted-content";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";

function renderComponent(post, { highlightTerm } = {}) {
  return render(
    <template>
      <PostCookedHtml @highlightTerm={{highlightTerm}} @post={{post}} />
    </template>
  );
}

module("Integration | Component | Post | PostCookedHtml", function (hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(function () {
    const store = getOwner(this).lookup("service:store");
    const topic = store.createRecord("topic", { id: 1 });
    const post = store.createRecord("post", {
      id: 123,
      post_number: 1,
      topic,
      like_count: 3,
      actions_summary: [{ id: 2, count: 1, hidden: false, can_act: true }],
    });

    this.post = post;
  });

  test("quotes with no username and no valid topic", async function (assert) {
    this.post.cooked = `<aside class=\"quote no-group quote-post-not-found\" data-username=\"unknown\" data-post=\"1\" data-topic=\"123456\">\n<blockquote>\n<p>abcd</p>\n</blockquote>\n</aside>\n<p>Testing the issue</p>`;

    await renderComponent(this.post);

    assert
      .dom("aside.quote .title")
      .hasText("unknown")
      .doesNotHaveAttribute("data-has-quote-controls")
      .doesNotHaveAttribute("data-can-toggle-quote")
      .doesNotHaveAttribute("data-can-navigate-to-post");
    assert.dom(".quote-controls").doesNotExist();
    assert.dom("blockquote").hasText("abcd");
  });

  test("localizes internal onebox cards using localized_oneboxes", async function (assert) {
    this.post.cooked = `<aside class="quote" data-post="2" data-topic="55">
      <div class="title">
        <div class="quote-controls"></div>
        <div class="quote-title__text-content"><a href="/t/sun/55/2">Original Title</a></div>
      </div>
      <blockquote>Original preview</blockquote>
    </aside>`;
    this.post.localized_oneboxes = [
      {
        topic_id: 55,
        post_number: 2,
        title: "孫子の兵法",
        excerpt: "戦わずして勝つ",
      },
    ];

    await renderComponent(this.post);

    assert
      .dom("aside.quote .title")
      .includesText("孫子の兵法")
      .doesNotIncludeText("Original Title");
    assert.dom("aside.quote blockquote").includesText("戦わずして勝つ");
  });

  test("swaps only the title when no excerpt is provided", async function (assert) {
    this.post.cooked = `<aside class="quote" data-post="1" data-topic="55">
      <div class="title">
        <div class="quote-controls"></div>
        <div class="quote-title__text-content"><a href="/t/sun/55/1">Original Title</a></div>
      </div>
      <blockquote>Original preview</blockquote>
    </aside>`;
    this.post.localized_oneboxes = [
      { topic_id: 55, post_number: 1, title: "孫子の兵法" },
    ];

    await renderComponent(this.post);

    assert.dom("aside.quote .title").includesText("孫子の兵法");
    assert.dom("aside.quote blockquote").includesText("Original preview");
  });

  test("leaves same-topic inline quotes (with data-username) untouched", async function (assert) {
    this.post.cooked = `<aside class="quote" data-username="sun" data-post="2" data-topic="55">
      <div class="title"><div class="quote-controls"></div>sun:</div>
      <blockquote>Original preview</blockquote>
    </aside>`;
    this.post.localized_oneboxes = [
      {
        topic_id: 55,
        post_number: 2,
        title: "孫子の兵法",
        excerpt: "戦わずして勝つ",
      },
    ];

    await renderComponent(this.post);

    assert
      .dom("aside.quote blockquote")
      .includesText("Original preview")
      .doesNotIncludeText("戦わずして勝つ");
  });

  test("it keeps the opened state of the `details` tag between renders", async function (assert) {
    this.post.cooked = `<details><summary>Quote Summary</summary><p>Quote Content</p></details>`;

    await renderComponent(this.post);

    assert
      .dom("details")
      .exists()
      .doesNotHaveAttribute("open", "the details tag is closed by default");

    await click("details > summary");
    assert
      .dom("details")
      .hasAttribute(
        "open",
        "",
        "the details tag is opened after clicking the summary"
      );

    this.post.cooked += '<p class="new-content">New Content</p>';
    await settled();
    assert
      .dom("p.new-content")
      .exists()
      .hasText("New Content", "ensure the cooked content was updated");
    assert
      .dom("details")
      .exists()
      .hasAttribute(
        "open",
        "",
        "the details tag remains opened after re-rendering"
      );

    await click("details > summary");
    assert
      .dom("details")
      .doesNotHaveAttribute(
        "open",
        "the details tag is closed after clicking the summary again"
      );

    this.post.cooked += '<p class="another-content">Another Content</p>';
    await settled();

    assert
      .dom("p.another-content")
      .exists()
      .hasText(
        "Another Content",
        "ensure the cooked content was updated again"
      );
    assert
      .dom("details")
      .exists()
      .doesNotHaveAttribute(
        "open",
        "the details tag remains closed after re-rendering"
      );
  });

  test("preserves decorator state across unmount/remount without storing decorator functions strongly", async function (assert) {
    let fetchCount = 0;
    pretender.get("/posts/by_number/1/2", () => {
      fetchCount += 1;
      return response({
        id: 456,
        post_number: 2,
        topic_id: 1,
        username: "alice",
        cooked: "<p>Full quoted post body</p>",
      });
    });

    this.post.cooked = `
      <details><summary>Summary</summary><p>Body</p></details>
      <aside class="quote" data-username="alice" data-post="2" data-topic="1">
        <div class="title"><div class="quote-controls"></div>alice:</div>
        <blockquote><p>Quoted excerpt</p></blockquote>
      </aside>
    `;

    const seenByStaticDecorator = [];
    function staticExtraDecorator(_el, { decoratorState }) {
      const count = (decoratorState.get("runs") ?? 0) + 1;
      decoratorState.set("runs", count);
      seenByStaticDecorator.push(count);
    }

    class State {
      @tracked visible = true;
      @tracked extraDecorators = [staticExtraDecorator, () => {}];
      decoratorState = trackedMap();
    }

    const state = new State();
    const post = this.post;

    await render(
      <template>
        {{#if state.visible}}
          <PostCookedHtml
            @decoratorState={{state.decoratorState}}
            @extraDecorators={{state.extraDecorators}}
            @post={{post}}
          />
        {{/if}}
      </template>
    );

    await click("details > summary");
    await click("aside.quote .quote-toggle");

    assert.dom("details").hasAttribute("open", "");
    assert.dom("aside.quote .expanded-quote").includesText("Full quoted post");
    assert.strictEqual(fetchCount, 1);

    // Simulate post cloaking and uncloaking with a fresh per-instance extra decorator
    state.visible = false;
    await settled();

    state.extraDecorators = [staticExtraDecorator, () => {}];
    state.visible = true;
    await settled();

    assert
      .dom("details")
      .hasAttribute("open", "", "details state persists across cloak/uncloak");
    assert
      .dom("aside.quote .expanded-quote")
      .includesText(
        "Full quoted post",
        "expanded quote state persists across cloak/uncloak"
      );
    assert.strictEqual(
      fetchCount,
      1,
      "cached quoted post is reused without refetching"
    );
    assert.deepEqual(
      seenByStaticDecorator,
      [1, 2],
      "static extra decorators retain their sub-state across cloak/uncloak"
    );
    assert.strictEqual(
      state.decoratorState.size,
      0,
      "decorator functions are not stored as strong keys on decoratorState"
    );
  });

  test("PostQuotedContent does not accumulate function keys in shared decoratorState across remounts", async function (assert) {
    class State {
      @tracked visible = true;
      decoratorState = trackedMap();
    }

    const state = new State();
    const post = this.post;

    await render(
      <template>
        {{#if state.visible}}
          <PostQuotedContent
            @collapsedContent="<p>Quoted text</p>"
            @decoratorState={{state.decoratorState}}
            @id="quote-id-1-2-0"
            @post={{post}}
            @quotedPostNumber={{2}}
            @quotedTopicId={{1}}
            @quotedUsername="alice"
          />
        {{/if}}
      </template>
    );

    for (let i = 0; i < 3; i++) {
      state.visible = false;
      await settled();
      state.visible = true;
      await settled();
    }

    const functionKeys = [...state.decoratorState.keys()].filter(
      (key) => typeof key === "function"
    );
    assert.strictEqual(
      functionKeys.length,
      0,
      "no per-instance decorator closures are retained in shared decoratorState"
    );
    assert.strictEqual(
      state.decoratorState.size,
      0,
      "unexpanded quote does not leak entries into decoratorState across remounts"
    );
  });
});
