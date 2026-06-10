export default function Loading() {
  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6 animate-pulse">
      {/* Header skeleton */}
      <div className="h-8 w-48 rounded-xl glass-light" />
      {/* Card skeletons */}
      <div className="h-36 rounded-2xl glass-light" />
      <div className="grid grid-cols-2 gap-4">
        <div className="h-28 rounded-2xl glass-light" />
        <div className="h-28 rounded-2xl glass-light" />
      </div>
      <div className="h-24 rounded-2xl glass-light" />
      <div className="h-24 rounded-2xl glass-light" />
      <div className="h-24 rounded-2xl glass-light" />
    </div>
  )
}
