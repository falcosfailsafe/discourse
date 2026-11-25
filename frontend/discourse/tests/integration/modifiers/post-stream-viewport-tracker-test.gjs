import { render, settled } from "@ember/test-helpers";
import { module, test } from "qunit";
import PostStreamViewportTracker, {
  disableCloaking,
  enableCloaking,
  preventCloaking,
} from "discourse/modifiers/post-stream-viewport-tracker";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";

async function waitForCloakingFlush() {
  // Exceed SCROLL_BATCH_INTERVAL_MS (10ms) debounce and flush the rAF callback.
  await new Promise((resolve) => setTimeout(resolve, 30));
  await new Promise((resolve) => requestAnimationFrame(() => resolve()));
  await settled();
}

function makeEntry(target, isIntersecting) {
  return {
    target,
    isIntersecting,
    intersectionRect: { height: isIntersecting ? 100 : 0 },
    intersectionRatio: isIntersecting ? 1 : 0,
  };
}

module(
  "Integration | Modifier | PostStreamViewportTracker | cloaking",
  function (hooks) {
    setupRenderingTest(hooks);

    let tracker;

    hooks.beforeEach(function () {
      enableCloaking();
      tracker = new PostStreamViewportTracker();
    });

    hooks.afterEach(function () {
      tracker.destroy();
      disableCloaking();
    });

    test("only invalidates posts whose cloaking state changes and caches style objects", async function (assert) {
      const posts = [1, 2, 3, 4, 5].map((n) => ({
        id: 100 + n,
        post_number: n,
      }));
      const evalCounts = Object.fromEntries(posts.map((p) => [p.id, 0]));
      const readCloakingData = (post) => {
        evalCounts[post.id]++;
        return tracker.getCloakingData(post);
      };
      const screenTrack = { setOnscreen() {} };
      const noop = () => {};

      await render(
        <template>
          <div
            class="post-stream-test"
            {{tracker.setup
              currentPostChanged=noop
              currentPostScrolled=noop
              eyeline=false
              headerOffset=0
              screenTrack=screenTrack
              topicId=42
            }}
          >
            {{#each posts key="id" as |post|}}
              {{#let (readCloakingData post) as |cloakingData|}}
                <div
                  class={{if cloakingData.active "post-stream--cloaked"}}
                  data-post-id={{post.id}}
                  data-post-number={{post.post_number}}
                  style={{cloakingData.style}}
                  {{tracker.registerPost post}}
                >
                  {{#unless cloakingData.active}}
                    <div style="height: 200px">Post {{post.post_number}}</div>
                  {{/unless}}
                </div>
              {{/let}}
            {{/each}}
          </div>
        </template>
      );

      const container = document.querySelector(".post-stream-test");
      const elements = posts.map((p) =>
        container.querySelector(`[data-post-id="${p.id}"]`)
      );

      // Let initial real IntersectionObserver callbacks settle before driving transitions.
      await waitForCloakingFlush();

      // Step 1: Posts 1 and 2 exit both the viewport and cloaking area while posts 3-5 remain visible.
      tracker.trackVisiblePosts(makeEntry(elements[0], false));
      tracker.trackVisiblePosts(makeEntry(elements[1], false));
      tracker.trackCloakedPosts(makeEntry(elements[0], false));
      tracker.trackCloakedPosts(makeEntry(elements[1], false));
      tracker.trackCloakedPosts(makeEntry(elements[2], true));
      tracker.trackCloakedPosts(makeEntry(elements[3], true));
      tracker.trackCloakedPosts(makeEntry(elements[4], true));
      await waitForCloakingFlush();

      assert
        .dom(elements[0])
        .hasClass("post-stream--cloaked", "post 1 is cloaked");
      assert
        .dom(elements[1])
        .hasClass("post-stream--cloaked", "post 2 is cloaked");
      assert
        .dom(elements[2])
        .doesNotHaveClass("post-stream--cloaked", "post 3 stays uncloaked");

      const post1DataBefore = tracker.getCloakingData(posts[0]);
      assert.true(post1DataBefore.active, "post 1 cloaking data is active");

      // Reset counters and observe style attribute writes while shifting boundary by 1 post.
      for (const p of posts) {
        evalCounts[p.id] = 0;
      }

      const styleMutatedIds = [];
      const observer = new MutationObserver((records) => {
        for (const record of records) {
          if (
            record.type === "attributes" &&
            record.attributeName === "style"
          ) {
            styleMutatedIds.push(Number(record.target.dataset.postId));
          }
        }
      });
      observer.observe(container, {
        subtree: true,
        attributes: true,
        attributeFilter: ["style"],
      });

      try {
        // Step 2: Post 3 exits; posts 1 and 2 remain cloaked, posts 4-5 stay visible.
        tracker.trackVisiblePosts(makeEntry(elements[2], false));
        tracker.trackCloakedPosts(makeEntry(elements[2], false));
        await waitForCloakingFlush();

        assert
          .dom(elements[2])
          .hasClass("post-stream--cloaked", "post 3 becomes cloaked");
        assert.strictEqual(
          tracker.getCloakingData(posts[0]),
          post1DataBefore,
          "cached cloaking data object and TrustedHTML style preserve identity"
        );
        assert.strictEqual(
          evalCounts[posts[0].id],
          0,
          "already-cloaked post 1 is not re-evaluated on boundary change"
        );
        assert.strictEqual(
          evalCounts[posts[1].id],
          0,
          "already-cloaked post 2 is not re-evaluated on boundary change"
        );
        assert.strictEqual(
          evalCounts[posts[2].id],
          1,
          "newly cloaked post 3 re-evaluates once"
        );
        assert.deepEqual(
          styleMutatedIds,
          [posts[2].id],
          "only the newly cloaked post receives a style attribute write"
        );

        // Step 3: preventCloaking toggles only the targeted post.
        evalCounts[posts[0].id] = 0;
        evalCounts[posts[1].id] = 0;
        evalCounts[posts[2].id] = 0;

        preventCloaking(posts[0].id, true);
        await settled();

        assert
          .dom(elements[0])
          .doesNotHaveClass(
            "post-stream--cloaked",
            "preventCloaking uncloaks the targeted post"
          );
        assert.strictEqual(
          evalCounts[posts[1].id],
          0,
          "other cloaked posts do not re-evaluate when preventCloaking changes"
        );
        assert.strictEqual(
          evalCounts[posts[2].id],
          0,
          "post 3 does not re-evaluate when preventCloaking changes for post 1"
        );

        preventCloaking(posts[0].id, false);
        await settled();

        assert
          .dom(elements[0])
          .hasClass(
            "post-stream--cloaked",
            "allowing cloaking again re-cloaks the post"
          );

        // Step 4: Explicit { above, below } signature remains compatible and cached.
        const explicitFirst = tracker.getCloakingData(posts[0], {
          above: 4,
          below: 5,
        });
        const explicitSecond = tracker.getCloakingData(posts[0], {
          above: 4,
          below: 5,
        });
        assert.strictEqual(
          explicitFirst,
          explicitSecond,
          "explicit boundary lookup reuses the cached cloaking payload"
        );
        assert.strictEqual(
          explicitFirst.style,
          explicitSecond.style,
          "explicit boundary lookup reuses the cached TrustedHTML instance"
        );
      } finally {
        observer.disconnect();
      }
    });
  }
);
