import { getOwner } from "@ember/owner";
import { click, render, settled } from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import TopicTimeline from "discourse/components/topic-timeline";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";

const POSTS_COUNT = 100;

function createMegaTopic(context, attrs = {}) {
  const topic = getOwner(context)
    .lookup("service:store")
    .createRecord("topic", {
      id: 1,
      highest_post_number: POSTS_COUNT,
      ...attrs,
    });
  topic.postStream.isMegaTopic = true;
  return topic;
}

module("Integration | Component | topic-timeline", function (hooks) {
  setupRenderingTest(hooks);

  test("fullscreen hides the summary button and shows the last post excerpt", async function (assert) {
    this.siteSettings.summary_timeline_button = true;
    const topic = createMegaTopic(this, { has_summary: true });
    sinon.stub(topic.postStream, "excerpt").resolves({ excerpt: "Last post" });
    const jumpTop = () => {};

    await render(
      <template>
        <TopicTimeline
          @enteredIndex={{99}}
          @fullscreen={{true}}
          @jumpTop={{jumpTop}}
          @model={{topic}}
        />
      </template>
    );

    assert.dom(".show-summary").doesNotExist();
    assert.dom(".post-excerpt").hasText("Last post");
  });

  test("the back button jumps to the last read post", async function (assert) {
    const topic = createMegaTopic(this, {
      last_read_post_id: 5500,
      last_read_post_number: 55,
    });
    const jumpToIndex = sinon.spy();

    await render(
      <template>
        <TopicTimeline
          @enteredIndex={{10}}
          @jumpToIndex={{jumpToIndex}}
          @model={{topic}}
        />
      </template>
    );
    await click(".timeline-last-read .back-button");

    assert.true(jumpToIndex.calledOnceWith(55));
  });

  test("shows the total posts count only when it fits", async function (assert) {
    const topic = createMegaTopic(this, { highest_post_number: 10_050 });
    const jumpTop = () => {};
    const sameLine = () => {
      const [current, total] = document.querySelectorAll(
        ".timeline-replies span"
      );
      return current.offsetTop === total.offsetTop;
    };

    await render(
      <template>
        <TopicTimeline @enteredIndex={{5000}} @model={{topic}} />
      </template>
    );
    assert.dom(".timeline-replies").hasText("5001 / 10050");
    assert.true(sameLine(), "the total fits next to the current post");

    await render(
      <template>
        <TopicTimeline
          @enteredIndex={{5000}}
          @fullscreen={{true}}
          @jumpTop={{jumpTop}}
          @model={{topic}}
        />
      </template>
    );
    assert.false(sameLine(), "the total wraps out of view");
  });

  test("updates padding directly on scroll without rewriting scrollarea style or rerendering unchanged post/date", async function (assert) {
    const topic = createMegaTopic(this, {
      last_read_post_id: 5500,
      last_read_post_number: 55,
    });
    topic.postStream.timelineLookup = [[1, 30]];
    const appEvents = this.owner.lookup("service:app-events");

    await render(
      <template>
        <TopicTimeline @enteredIndex={{10}} @model={{topic}} />
      </template>
    );

    assert.dom(".timeline-replies").hasText("11 / 100");
    assert.dom(".timeline-last-read").exists();

    const scrollarea = document.querySelector(".timeline-scrollarea");
    const scroller = document.querySelector(".timeline-scroller");
    const [beforePadding, afterPadding] =
      document.querySelectorAll(".timeline-padding");

    let scrollareaStyleMutations = 0;
    const scrollareaObserver = new MutationObserver(() => {
      scrollareaStyleMutations += 1;
    });
    scrollareaObserver.observe(scrollarea, {
      attributes: true,
      attributeFilter: ["style"],
    });

    let scrollerMutations = 0;
    const scrollerObserver = new MutationObserver(() => {
      scrollerMutations += 1;
    });
    scrollerObserver.observe(scroller, {
      subtree: true,
      childList: true,
      characterData: true,
    });

    try {
      const heights = [];
      for (const percent of [0.101, 0.104, 0.108]) {
        appEvents.trigger("topic:current-post-scrolled", {
          postIndex: 11,
          percent,
        });
        await settled();
        heights.push(parseFloat(beforePadding.style.height));
      }

      assert.strictEqual(
        scrollareaStyleMutations,
        0,
        "scrollarea style is not rewritten when height is unchanged"
      );
      assert.strictEqual(
        scrollerMutations,
        0,
        "scroller DOM is untouched when post number and date are unchanged"
      );
      assert.true(
        heights[0] < heights[1],
        "before padding height increases on the second scroll event"
      );
      assert.true(
        heights[1] < heights[2],
        "before padding height increases on the third scroll event"
      );
      assert.true(
        parseFloat(afterPadding.style.height) > 0,
        "after padding height stays updated"
      );

      // Scrolling onto the last-read position updates the counter and hides the back indicator
      appEvents.trigger("topic:current-post-scrolled", {
        postIndex: 55,
        percent: 0.54,
      });
      await settled();

      assert.dom(".timeline-replies").hasText("55 / 100");
      assert
        .dom(".timeline-last-read")
        .doesNotExist("back indicator hides when scroller reaches last-read");

      // Scrolling back up restores the back indicator
      appEvents.trigger("topic:current-post-scrolled", {
        postIndex: 11,
        percent: 0.1,
      });
      await settled();

      assert.dom(".timeline-replies").hasText("11 / 100");
      assert
        .dom(".timeline-last-read")
        .exists("back indicator reappears when scrolling away from last-read");
    } finally {
      scrollareaObserver.disconnect();
      scrollerObserver.disconnect();
    }
  });
});
