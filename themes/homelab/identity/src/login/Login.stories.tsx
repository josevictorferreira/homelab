import type { Meta, StoryObj } from "@storybook/react";
import { LoginStory, RegisterStory, ForgotPasswordStory, ErrorStory } from "./KcPageStory";

const meta: Meta = {
  title: "Pages/Login",
  parameters: {
    layout: "fullscreen",
  },
};

export default meta;
type Story = StoryObj<typeof LoginStory>;

export const Login: Story = {
  render: () => <LoginStory />,
};

export const Register: Story = {
  render: () => <RegisterStory />,
};

export const ForgotPassword: Story = {
  render: () => <ForgotPasswordStory />,
};

export const Error: Story = {
  render: () => <ErrorStory />,
};
